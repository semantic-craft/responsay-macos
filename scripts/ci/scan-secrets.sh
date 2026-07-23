#!/usr/bin/env bash
set -euo pipefail

# Non-interactive SSH sessions on developer Macs often omit Homebrew from PATH.
# Resolve the two mandatory scanners from standard Homebrew prefixes without
# depending on a user's interactive shell configuration.
for tool_directory in /opt/homebrew/bin /usr/local/bin; do
  if [[ -d "${tool_directory}" ]]; then
    PATH="${tool_directory}:${PATH}"
  fi
done
export PATH

ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
TEMP_BASE="${TMPDIR:-/tmp}"
TEMP_BASE="${TEMP_BASE%/}"
AUDIT_DIR="$(mktemp -d "${TEMP_BASE}/responsay-public-scan.XXXXXX")"
SNAPSHOT="${AUDIT_DIR}/tracked-worktree"
failures=0

cleanup() {
  case "${AUDIT_DIR}" in
    "${TEMP_BASE}"/responsay-public-scan.*)
      /bin/rm -rf -- "${AUDIT_DIR}"
      ;;
  esac
}
trap cleanup EXIT HUP INT TERM

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'secret scan: required tool is missing: %s\n' "$1" >&2
    exit 2
  fi
}

run_gitleaks() {
  local label="$1"
  shift
  local status
  set +e
  gitleaks "$@" \
    --no-banner \
    --redact=100 \
    --exit-code 1 \
    --config "${ROOT}/.gitleaks.toml" \
    --report-format json \
    --report-path "${AUDIT_DIR}/${label}.json" \
    >"${AUDIT_DIR}/${label}.stdout" 2>"${AUDIT_DIR}/${label}.stderr"
  status=$?
  set -e

  case "${status}" in
    0)
      printf 'secret scan: Gitleaks %s passed.\n' "${label}"
      ;;
    1)
      printf 'secret scan: Gitleaks %s found candidate secret(s); raw report was quarantined.\n' "${label}" >&2
      failures=$((failures + 1))
      ;;
    *)
      printf 'secret scan: Gitleaks %s failed with tool status %d; raw diagnostics were quarantined.\n' "${label}" "${status}" >&2
      failures=$((failures + 1))
      ;;
  esac
}

run_trufflehog() {
  local label="$1"
  shift
  local status
  local report="${AUDIT_DIR}/${label}.jsonl"
  set +e
  trufflehog "$@" \
    --no-update \
    --no-verification \
    --results=unverified,filtered_unverified \
    --fail-on-scan-errors \
    --json \
    --log-level=-1 \
    >"${report}" 2>"${AUDIT_DIR}/${label}.stderr"
  status=$?
  set -e

  if (( status != 0 )); then
    printf 'secret scan: TruffleHog %s failed with tool status %d; raw diagnostics were quarantined.\n' "${label}" "${status}" >&2
    failures=$((failures + 1))
  elif [[ -s "${report}" ]]; then
    printf 'secret scan: TruffleHog %s found candidate secret(s); raw report was quarantined.\n' "${label}" >&2
    failures=$((failures + 1))
  else
    printf 'secret scan: TruffleHog %s passed.\n' "${label}"
  fi
}

require_tool gitleaks
require_tool trufflehog

mkdir -p "${SNAPSHOT}"
while IFS= read -r -d '' path; do
  [[ -f "${ROOT}/${path}" ]] || continue
  mkdir -p "${SNAPSHOT}/$(dirname "${path}")"
  cp -p "${ROOT}/${path}" "${SNAPSHOT}/${path}"
done < <(git -C "${ROOT}" ls-files -z)

run_gitleaks history git --log-opts=--all "${ROOT}"
run_gitleaks worktree dir "${SNAPSHOT}"
run_trufflehog history git "file://${ROOT}"
run_trufflehog worktree filesystem "${SNAPSHOT}"

if (( failures > 0 )); then
  printf 'secret scan failed with %d scanner failure(s). No raw report was retained.\n' "${failures}" >&2
  exit 1
fi

printf 'secret scan passed with Gitleaks and TruffleHog. No raw report was retained.\n'
