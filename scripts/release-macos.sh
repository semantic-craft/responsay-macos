#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
TAG="${1:-}"
TEMP_BASE="${TMPDIR:-/tmp}"
TEMP_BASE="${TEMP_BASE%/}"
WORK_DIR="$(mktemp -d "${TEMP_BASE}/responsay-release.XXXXXX")"
DERIVED_DATA="${WORK_DIR}/DerivedData"
KEYCHAIN_PATH="${WORK_DIR}/release.keychain-db"
NOTARY_DIR="${WORK_DIR}/notary"
OUTPUT_DIR="${ROOT}/build/release"

cleanup() {
  security delete-keychain "${KEYCHAIN_PATH}" >/dev/null 2>&1 || true
  case "${WORK_DIR}" in
    "${TEMP_BASE}"/responsay-release.*)
      /bin/rm -rf -- "${WORK_DIR}"
      ;;
  esac
}
trap cleanup EXIT HUP INT TERM

fail() {
  printf 'release: %s\n' "$1" >&2
  exit 1
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || fail "required tool is missing: $1"
}

require_env() {
  local name="$1"
  [[ -n "${!name:-}" ]] || fail "required environment secret is missing: ${name}"
}

redact_log() {
  sed -E \
    -e 's#/Users/[^/[:space:]]+#/Users/[REDACTED]#g' \
    -e 's/[A-F0-9]{40}/[SIGNING_IDENTITY]/g' \
    -e 's/[A-Z0-9]{10}/[TEAM_ID]/g' \
    "$1" | tail -n 160
}

# First value for a key in notarytool JSON. Its history is newest-first, so the first
# match is the most recent submission. Avoids a jq dependency for two scalar reads.
json_first_value() {
  grep -o "\"$2\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$1" | head -1 | sed 's/.*"\([^"]*\)"$/\1/'
}

notarize() {
  local artifact="$1"
  local label="$2"
  local result="${NOTARY_DIR}/${label}.json"
  local info="${NOTARY_DIR}/${label}-info.json"
  local diagnostics="${NOTARY_DIR}/${label}.stderr"
  local attempt
  local -a credential_args

  if (( LOCAL_MODE )); then
    if [[ -n "${RESPONSAY_ASC_KEY_PATH:-}" ]]; then
      credential_args=(
        --key "${RESPONSAY_ASC_KEY_PATH}"
        --key-id "${RESPONSAY_ASC_KEY_ID}"
        --issuer "${RESPONSAY_ASC_ISSUER_ID}"
      )
    else
      credential_args=(--keychain-profile "${NOTARY_PROFILE}")
    fi
  else
    credential_args=(
      --key "${NOTARY_DIR}/AuthKey.p8"
      --key-id "${RESPONSAY_ASC_KEY_ID}"
      --issuer "${RESPONSAY_ASC_ISSUER_ID}"
    )
  fi

  # `--wait` holds one long connection open for the whole notarization and drops on a
  # flaky link, so upload and waiting are separated: submit, then poll. A dropped poll
  # costs one cheap query instead of re-uploading.
  #
  # The upload itself is retried, but a timeout can also mean the bytes arrived and only
  # the reply was lost. Before re-uploading, look for a submission of the same artifact
  # that just appeared, and adopt it — otherwise every retry queues another duplicate.
  local artifact_name submission_id=""
  artifact_name="$(basename "${artifact}")"

  for attempt in 1 2 3; do
    if xcrun notarytool submit "${artifact}" \
      "${credential_args[@]}" \
      --output-format json \
      >"${result}" 2>"${diagnostics}"; then
      submission_id="$(json_first_value "${result}" id)"
      [[ -n "${submission_id}" ]] && break
    fi

    printf 'release: notarization upload attempt %d for %s did not complete.\n' "${attempt}" "${label}" >&2
    sleep 15
    if xcrun notarytool history "${credential_args[@]}" --output-format json \
      >"${info}" 2>/dev/null; then
      if [[ "$(json_first_value "${info}" name)" == "${artifact_name}" ]]; then
        submission_id="$(json_first_value "${info}" id)"
        if [[ -n "${submission_id}" ]]; then
          printf 'release: the upload had in fact registered; adopting submission %s.\n' "${submission_id}" >&2
          break
        fi
      fi
    fi
  done

  if [[ -z "${submission_id}" ]]; then
    printf 'release: could not upload %s for notarization. Sanitized diagnostics follow.\n' "${label}" >&2
    redact_log "${diagnostics}" >&2
    return 1
  fi
  printf 'release: %s uploaded for notarization (%s); waiting for Apple.\n' "${label}" "${submission_id}"

  # Apple usually answers in a few minutes, but the queue can stall for far longer. Waiting
  # is cheaper than starting over: a re-run means another build and another upload, and the
  # submission would still be sitting in the same queue.
  local status=""
  local unreachable=0
  local -i poll_seconds=20
  local -i max_polls=${RESPONSAY_NOTARY_POLLS:-360}
  for attempt in $(seq 1 "${max_polls}"); do
    if (( attempt > 1 && attempt % 15 == 1 )); then
      printf 'release: still waiting on %s (%d minutes elapsed).\n' \
        "${label}" "$(( (attempt - 1) * poll_seconds / 60 ))"
    fi
    if xcrun notarytool info "${submission_id}" \
      "${credential_args[@]}" \
      --output-format json \
      >"${info}" 2>"${diagnostics}"; then
      unreachable=0
      status="$(sed -n 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${info}" | head -1)"
      case "${status}" in
        Accepted)
          printf 'release: Apple notarization accepted %s.\n' "${label}"
          return 0
          ;;
        "In Progress")
          ;;
        *)
          printf 'release: Apple notarization returned %s for %s. Log follows.\n' "${status}" "${label}" >&2
          xcrun notarytool log "${submission_id}" "${credential_args[@]}" 2>/dev/null | head -60 >&2 || true
          return 1
          ;;
      esac
    else
      # A credential fault never heals by waiting, and the keychain item can disappear
      # mid-run. Treating that as a flaky network burns the whole timeout for nothing.
      if grep -qiE 'no keychain password item|unable to authenticate|invalid credential|not authorized' \
        "${diagnostics}" 2>/dev/null; then
        printf 'release: notarization credentials stopped working while waiting on %s.\n' "${submission_id}" >&2
        redact_log "${diagnostics}" >&2
        return 1
      fi
      unreachable=$((unreachable + 1))
      if (( unreachable == 1 )); then
        printf 'release: cannot reach the notary service; still waiting on %s.\n' "${submission_id}" >&2
      fi
      if (( unreachable >= 15 )); then
        printf 'release: %d consecutive status queries failed; this is not a brief glitch.\n' "${unreachable}" >&2
        redact_log "${diagnostics}" >&2
        return 1
      fi
    fi
    sleep "${poll_seconds}"
  done

  printf 'release: gave up waiting for notarization of %s after %d minutes.\n' \
    "${label}" "$(( max_polls * poll_seconds / 60 ))" >&2
  printf 'release: the submission may still finish. Check with:\n' >&2
  printf '  xcrun notarytool info %s --keychain-profile %s\n' "${submission_id}" "${NOTARY_PROFILE:-<profile>}" >&2
  return 1
}

for tool in base64 codesign git hdiutil security shasum xcodebuild xcodegen xcrun; do
  require_tool "${tool}"
done

# Two credential sources. A hosted runner has no keychain, so CI injects the signing
# certificate and an App Store Connect key as environment secrets. On a maintainer's Mac
# both already live in the login keychain, so nothing needs to be exported: set no
# secrets and the release signs with the identity that is already there.
LOCAL_MODE=0
[[ -z "${RESPONSAY_DEVELOPER_ID_P12_BASE64:-}" ]] && LOCAL_MODE=1

if (( LOCAL_MODE )); then
  NOTARY_PROFILE="${RESPONSAY_NOTARY_PROFILE:-responsay-notary}"
  # An App Store Connect key file is preferred when given: it is a plain file, so it
  # cannot vanish mid-run the way a keychain credential item can.
  if [[ -n "${RESPONSAY_ASC_KEY_PATH:-}" ]]; then
    [[ -f "${RESPONSAY_ASC_KEY_PATH}" ]] || fail "RESPONSAY_ASC_KEY_PATH does not point at a file"
    require_env RESPONSAY_ASC_KEY_ID
    require_env RESPONSAY_ASC_ISSUER_ID
    printf 'release: local mode — signing with the login keychain, notarizing with an App Store Connect key.\n'
  else
    printf 'release: local mode — signing with the login keychain, notarizing via profile %s.\n' "${NOTARY_PROFILE}"
  fi
else
  for name in \
    RESPONSAY_DEVELOPER_ID_P12_BASE64 \
    RESPONSAY_DEVELOPER_ID_P12_PASSWORD \
    RESPONSAY_APPLE_TEAM_ID \
    RESPONSAY_ASC_KEY_P8_BASE64 \
    RESPONSAY_ASC_KEY_ID \
    RESPONSAY_ASC_ISSUER_ID; do
    require_env "${name}"
  done
  [[ "${RESPONSAY_APPLE_TEAM_ID}" =~ ^[A-Z0-9]{10}$ ]] || fail "Apple Team ID has an invalid format"
fi

[[ "${TAG}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "release tag must look like v1.2.3"

cd "${ROOT}"
scripts/ci/public-source-gate.sh

VERSION="$(sed -n 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"\([^"]*\)".*/\1/p' project.yml | head -1)"
BUILD_NUMBER="$(sed -n 's/^[[:space:]]*CURRENT_PROJECT_VERSION:[[:space:]]*"\([^"]*\)".*/\1/p' project.yml | head -1)"
[[ "${TAG}" == "v${VERSION}" ]] || fail "tag does not match MARKETING_VERSION"
[[ -n "${BUILD_NUMBER}" ]] || fail "CURRENT_PROJECT_VERSION is missing"

mkdir -p "${NOTARY_DIR}" "${OUTPUT_DIR}"
# The name is deliberately constant. The site's download button is a permanent redirect to
# `releases/latest/download/Responsay.dmg`, which resolves by filename — a versioned name
# makes that link 404 the moment a release lands.
DMG_NAME="Responsay.dmg"
DMG_PATH="${OUTPUT_DIR}/${DMG_NAME}"
SHA_PATH="${DMG_PATH}.sha256"
APPCAST_PATH="${OUTPUT_DIR}/appcast.xml"
[[ ! -e "${DMG_PATH}" && ! -e "${SHA_PATH}" && ! -e "${APPCAST_PATH}" ]] || fail "release output already exists; use a clean runner checkout"

if (( LOCAL_MODE )); then
  # The certificate is already in the login keychain. Find it there and read the team
  # from the identity itself, so a local release needs no configuration at all.
  IDENTITY_RECORD="$(security find-identity -v -p codesigning | grep 'Developer ID Application' | head -1 || true)"
  [[ -n "${IDENTITY_RECORD}" ]] || fail "no Developer ID Application identity found in the login keychain"
  TEAM_ID="$(sed -E 's/.*\(([A-Z0-9]{10})\).*/\1/' <<< "${IDENTITY_RECORD}")"
  [[ "${TEAM_ID}" =~ ^[A-Z0-9]{10}$ ]] || fail "could not read the team from the Developer ID identity"
  if [[ -n "${RESPONSAY_APPLE_TEAM_ID:-}" && "${TEAM_ID}" != "${RESPONSAY_APPLE_TEAM_ID}" ]]; then
    fail "the Developer ID identity in the keychain does not match RESPONSAY_APPLE_TEAM_ID"
  fi
  if [[ -z "${RESPONSAY_ASC_KEY_PATH:-}" ]]; then
    xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" >/dev/null 2>&1 ||
      fail "notarytool profile ${NOTARY_PROFILE} is not set up. Create it once with: xcrun notarytool store-credentials \"${NOTARY_PROFILE}\" --apple-id <apple-id> --team-id ${TEAM_ID}"
  fi
else
  TEAM_ID="${RESPONSAY_APPLE_TEAM_ID}"
  printf '%s' "${RESPONSAY_DEVELOPER_ID_P12_BASE64}" | /usr/bin/base64 -D >"${NOTARY_DIR}/developer-id.p12"
  printf '%s' "${RESPONSAY_ASC_KEY_P8_BASE64}" | /usr/bin/base64 -D >"${NOTARY_DIR}/AuthKey.p8"
  chmod 600 "${NOTARY_DIR}/developer-id.p12" "${NOTARY_DIR}/AuthKey.p8"

  KEYCHAIN_PASSWORD="$(openssl rand -hex 24)"
  security create-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN_PATH}"
  security set-keychain-settings -lut 21600 "${KEYCHAIN_PATH}"
  security unlock-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN_PATH}"
  security import "${NOTARY_DIR}/developer-id.p12" \
    -k "${KEYCHAIN_PATH}" \
    -P "${RESPONSAY_DEVELOPER_ID_P12_PASSWORD}" \
    -T /usr/bin/codesign \
    -T /usr/bin/security >/dev/null
  security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s \
    -k "${KEYCHAIN_PASSWORD}" \
    "${KEYCHAIN_PATH}" >/dev/null
  security list-keychains -d user -s "${KEYCHAIN_PATH}"

  IDENTITY_RECORD="$(security find-identity -v -p codesigning "${KEYCHAIN_PATH}" | grep 'Developer ID Application' | head -1 || true)"
  [[ "${IDENTITY_RECORD}" == *"(${TEAM_ID})"* ]] || fail "Developer ID certificate does not match the configured Apple Team ID"
fi

IDENTITY_HASH="$(awk '{print $2}' <<< "${IDENTITY_RECORD}")"
[[ "${IDENTITY_HASH}" =~ ^[A-F0-9]{40}$ ]] || fail "Developer ID signing identity was not resolved"

xcodegen generate >/dev/null
BUILD_LOG="${WORK_DIR}/xcodebuild.log"
if ! xcodebuild \
  -scheme ResponsayMac \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "${DERIVED_DATA}" \
  build \
  CODE_SIGNING_ALLOWED=NO \
  >"${BUILD_LOG}" 2>&1; then
  printf 'release: Xcode build failed. Sanitized diagnostics follow.\n' >&2
  redact_log "${BUILD_LOG}" >&2
  exit 1
fi

APP_PATH="${DERIVED_DATA}/Build/Products/Release/Responsay.app"
[[ -d "${APP_PATH}" ]] || fail "Xcode did not produce Responsay.app"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP_PATH}/Contents/Info.plist")" == "${VERSION}" ]] || fail "built app version mismatch"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${APP_PATH}/Contents/Info.plist")" == "${BUILD_NUMBER}" ]] || fail "built app number mismatch"

# Sign inside-out: every nested bundle on its own, deepest first, then the app last.
# `--deep` looks equivalent but Apple documents it as unsuitable for distribution — it
# applies the outer options to nested code that has its own requirements, and Sparkle
# ships an Updater.app plus two XPC services that must each carry their own signature.
while IFS= read -r nested; do
  printf 'release: signing %s\n' "${nested#"${APP_PATH}"/}"
  codesign --force --options runtime --timestamp --sign "${IDENTITY_HASH}" "${nested}"
done < <(
  {
    find "${APP_PATH}/Contents" \
      \( -name '*.framework' -o -name '*.xpc' -o -name '*.app' -o -name '*.dylib' \) -print
    # Helper executables that live inside a framework without being a bundle of their own.
    # Sparkle ships Autoupdate this way; signing the enclosing framework does not cover it,
    # and notarization rejects it as unsigned.
    find "${APP_PATH}/Contents/Frameworks" -type f -perm +111 -print 2>/dev/null |
      while IFS= read -r candidate; do
        case "$(/usr/bin/file -b "${candidate}")" in
          *Mach-O*) printf '%s\n' "${candidate}" ;;
        esac
      done
  } |
    sort -u |
    awk '{ print gsub(/\//, "/"), $0 }' |
    sort -rn |
    cut -d' ' -f2-
)

codesign --force --options runtime --timestamp \
  --sign "${IDENTITY_HASH}" \
  --entitlements "${ROOT}/macOS/Responsay.entitlements" \
  "${APP_PATH}"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"

SIGNATURE_INFO="${WORK_DIR}/signature.txt"
codesign -d --verbose=4 "${APP_PATH}" 2>"${SIGNATURE_INFO}"
grep -Fq "TeamIdentifier=${TEAM_ID}" "${SIGNATURE_INFO}" || fail "built app Team ID mismatch"

APP_ZIP="${WORK_DIR}/Responsay-app.zip"
ditto -c -k --keepParent "${APP_PATH}" "${APP_ZIP}"
notarize "${APP_ZIP}" app
xcrun stapler staple "${APP_PATH}"
xcrun stapler validate "${APP_PATH}"
/usr/sbin/spctl --assess --type execute --context context:primary-signature --verbose=2 "${APP_PATH}"

DMG_STAGE="${WORK_DIR}/dmg-root"
mkdir -p "${DMG_STAGE}"
ditto "${APP_PATH}" "${DMG_STAGE}/Responsay.app"
ln -s /Applications "${DMG_STAGE}/Applications"
hdiutil create \
  -volname 'Responsay Installer' \
  -srcfolder "${DMG_STAGE}" \
  -format UDZO \
  "${DMG_PATH}" >/dev/null
codesign --force --timestamp --sign "${IDENTITY_HASH}" "${DMG_PATH}"
notarize "${DMG_PATH}" dmg
xcrun stapler staple "${DMG_PATH}"
xcrun stapler validate "${DMG_PATH}"
/usr/sbin/spctl --assess --type open --context context:primary-signature --verbose=2 "${DMG_PATH}"

(
  cd "${OUTPUT_DIR}"
  shasum -a 256 "${DMG_NAME}" >"${DMG_NAME}.sha256"
)

# Where the DMG will be downloaded from. Locally the artifact goes to the releases
# repository that serves the live Sparkle feed; in CI it is attached to this repository's
# release. Override with RESPONSAY_DOWNLOAD_URL_PREFIX when hosting moves.
if (( LOCAL_MODE )); then
  DEFAULT_URL_PREFIX="https://github.com/semantic-craft/responsay-releases/releases/download/${TAG}/"
else
  DEFAULT_URL_PREFIX="https://github.com/semantic-craft/responsay-macos/releases/download/${TAG}/"
fi
DOWNLOAD_URL_PREFIX="${RESPONSAY_DOWNLOAD_URL_PREFIX:-${DEFAULT_URL_PREFIX}}"

if (( LOCAL_MODE )) || [[ -n "${RESPONSAY_SPARKLE_ED_KEY_BASE64:-}" ]]; then
  GENERATE_APPCAST="$(find "${DERIVED_DATA}/SourcePackages/artifacts" -path '*/Sparkle/bin/generate_appcast' -type f -print -quit)"
  [[ -x "${GENERATE_APPCAST}" ]] || fail "Sparkle generate_appcast tool was not resolved"
  APPCAST_DIR="${WORK_DIR}/appcast"
  mkdir -p "${APPCAST_DIR}"
  cp "${DMG_PATH}" "${APPCAST_DIR}/${DMG_NAME}"
  APPCAST_LOG="${WORK_DIR}/generate-appcast.log"
  if (( LOCAL_MODE )); then
    # No key file: generate_appcast reads the EdDSA private key from the login keychain,
    # which is where Sparkle's generate_keys put it.
    appcast_ok=0
    "${GENERATE_APPCAST}" \
      --download-url-prefix "${DOWNLOAD_URL_PREFIX}" \
      "${APPCAST_DIR}" \
      >"${APPCAST_LOG}" 2>&1 && appcast_ok=1
  else
    appcast_ok=0
    printf '%s' "${RESPONSAY_SPARKLE_ED_KEY_BASE64}" | /usr/bin/base64 -D | \
      "${GENERATE_APPCAST}" \
        --ed-key-file - \
        --download-url-prefix "${DOWNLOAD_URL_PREFIX}" \
        "${APPCAST_DIR}" \
        >"${APPCAST_LOG}" 2>&1 && appcast_ok=1
  fi
  if (( ! appcast_ok )); then
    printf 'release: Sparkle appcast generation failed. Sanitized diagnostics follow.\n' >&2
    redact_log "${APPCAST_LOG}" >&2
    exit 1
  fi
  [[ -f "${APPCAST_DIR}/appcast.xml" ]] || fail "Sparkle did not produce appcast.xml"
  cp "${APPCAST_DIR}/appcast.xml" "${APPCAST_PATH}"
else
  printf 'release: Sparkle private key not configured; appcast generation was skipped.\n'
fi

printf 'release: created signed and notarized %s\n' "${DMG_PATH}"
printf 'release: created checksum %s\n' "${SHA_PATH}"
[[ -f "${APPCAST_PATH}" ]] && printf 'release: created Sparkle feed %s\n' "${APPCAST_PATH}"
