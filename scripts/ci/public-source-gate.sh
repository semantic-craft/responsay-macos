#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
cd "${ROOT}"

failures=0

reject() {
  printf 'public-source gate: %s\n' "$1" >&2
  failures=$((failures + 1))
}

allowed_path() {
  case "$1" in
    .github/workflows/ci.yml|.github/workflows/release.yml)
      return 0
      ;;
    .gitignore|.gitleaks.toml|CONTRIBUTING.md|LICENSE|README.md|THIRD_PARTY_NOTICES.md|project.yml)
      return 0
      ;;
    docs/RELEASING.md)
      return 0
      ;;
    Packages/ResponsayCore/*|Tests/ResponsayMacTests/*|macOS/*)
      return 0
      ;;
    scripts/fetch-sherpa-onnx.sh|scripts/release-macos.sh|scripts/ci/public-source-gate.sh|scripts/ci/scan-secrets.sh)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

file_size() {
  /usr/bin/stat -f '%z' "$1" 2>/dev/null || /usr/bin/stat -c '%s' "$1"
}

while IFS= read -r -d '' path; do
  if ! allowed_path "${path}"; then
    reject "tracked path is outside the public allowlist: ${path}"
    continue
  fi

  if [[ -L "${path}" ]]; then
    reject "tracked symlinks are not allowed: ${path}"
    continue
  fi

  if [[ -f "${path}" ]] && (( $(file_size "${path}") > 20971520 )); then
    reject "tracked file exceeds 20 MiB: ${path}"
  fi
done < <(git ls-files -z)

if git ls-files -s | awk '$1 == "120000" || $1 == "160000" { found = 1 } END { exit(found ? 0 : 1) }'; then
  reject "tracked symlinks or submodules are not allowed"
fi

check_content() {
  local label="$1"
  local pattern="$2"
  local matches
  matches="$(git grep -I -l -E "${pattern}" -- . \
    ':(exclude).gitleaks.toml' \
    ':(exclude)scripts/ci/public-source-gate.sh' \
    ':(exclude)Packages/ResponsayCore/Sources/ResponsayCore/Hotword/DictationLexicalProfile.swift' \
    2>/dev/null || true)"
  if [[ -n "${matches}" ]]; then
    while IFS= read -r path; do
      [[ -n "${path}" ]] && reject "${label}: ${path}"
    done <<< "${matches}"
  fi
}

check_content \
  "user-specific absolute path" \
  '(/Users/[[:alnum:]_.-]+|/Volumes/[[:alnum:]_. -]+|[A-Za-z]:\\Users\\[[:alnum:]_. -]+)'
check_content \
  "private-key material" \
  '-----BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----'
check_content \
  "fixed Apple signing metadata" \
  "(DEVELOPMENT_TEAM|TeamIdentifier|com\\.apple\\.developer\\.team-identifier)[[:space:]]*[:=][[:space:]]*[\"']?[A-Z0-9]{10}"

if (( failures > 0 )); then
  printf 'public-source gate failed with %d violation(s).\n' "${failures}" >&2
  exit 1
fi

printf 'public-source gate passed (%s tracked files).\n' "$(git ls-files | wc -l | tr -d ' ')"
