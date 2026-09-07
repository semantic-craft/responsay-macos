#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
PHASE="${1:-}"
TAG="${2:-}"
OUTPUT_DIR="${ROOT}/build/release"
DMG_PATH="${OUTPUT_DIR}/Responsay.dmg"
SHA_PATH="${DMG_PATH}.sha256"
NEW_ITEM_APPCAST="${OUTPUT_DIR}/appcast.xml"
FULL_APPCAST="${ROOT}/appcast.xml"
BUCKET="${RESPONSAY_R2_BUCKET:-responsay-updates}"
PUBLIC_BASE_URL="${RESPONSAY_UPDATE_BASE_URL:-https://updates.responsay.com}"
PUBLIC_BASE_URL="${PUBLIC_BASE_URL%/}"
if [[ -n "${RESPONSAY_WRANGLER:-}" ]]; then
  WRANGLER_COMMAND=("${RESPONSAY_WRANGLER}")
else
  WRANGLER_COMMAND=(npx --yes wrangler@4.123.0)
fi
TEMP_BASE="${TMPDIR:-/tmp}"
TEMP_BASE="${TEMP_BASE%/}"
VERIFY_DIR="$(mktemp -d "${TEMP_BASE}/responsay-publish.XXXXXX")"

cleanup() {
  case "${VERIFY_DIR}" in
    "${TEMP_BASE}"/responsay-publish.*)
      for verify_file in Responsay.dmg existing-Responsay.dmg appcast.xml live-appcast.xml versioned.sha256; do
        [[ -f "${VERIFY_DIR}/${verify_file}" ]] && unlink "${VERIFY_DIR}/${verify_file}"
      done
      rmdir "${VERIFY_DIR}"
      ;;
  esac
}
trap cleanup EXIT HUP INT TERM

fail() {
  printf 'publish: %s\n' "$1" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "required file is missing: $1"
}

put_object() {
  local key="$1"
  local file="$2"
  local content_type="$3"
  local cache_control="$4"

  "${WRANGLER_COMMAND[@]}" r2 object put "${BUCKET}/${key}" \
    --file="${file}" \
    --content-type="${content_type}" \
    --cache-control="${cache_control}" \
    --remote
}

[[ "${PHASE}" == artifacts || "${PHASE}" == activate ]] || fail "usage: publish-update-r2.sh artifacts|activate v1.2.3"
[[ "${TAG}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "release tag must look like v1.2.3"
for tool in curl shasum xcrun python3; do
  command -v "${tool}" >/dev/null 2>&1 || fail "required tool is missing: ${tool}"
done
if [[ -n "${RESPONSAY_WRANGLER:-}" ]]; then
  command -v "${RESPONSAY_WRANGLER}" >/dev/null 2>&1 ||
    fail "RESPONSAY_WRANGLER does not point to an executable"
else
  command -v npx >/dev/null 2>&1 || fail "npx is required to run the pinned Wrangler release"
fi

require_file "${DMG_PATH}"
require_file "${SHA_PATH}"
require_file "${NEW_ITEM_APPCAST}"
require_file "${FULL_APPCAST}"

EXPECTED_URL="${PUBLIC_BASE_URL}/releases/${TAG}/Responsay.dmg"
grep -Fq "url=\"${EXPECTED_URL}\"" "${NEW_ITEM_APPCAST}" ||
  fail "generated appcast does not point at ${EXPECTED_URL}"

# Compare parsed release metadata, not just a build number. Check the live feed before
# any write so a retry of an old tag cannot downgrade the stable download or appcast.
LIVE_APPCAST="${VERIFY_DIR}/live-appcast.xml"
if ! LIVE_STATUS="$(curl -sS -o "${LIVE_APPCAST}" -w '%{http_code}' \
  "${PUBLIC_BASE_URL}/appcast.xml?preflight=${TAG}&at=$(date +%s)")"; then
  fail "could not read the current public appcast"
fi
case "${LIVE_STATUS}" in
  200) ;;
  404) unlink "${LIVE_APPCAST}" ;;
  *) fail "unexpected HTTP ${LIVE_STATUS} while checking current appcast" ;;
esac

python3 - "${TAG}" "${DMG_PATH}" "${NEW_ITEM_APPCAST}" "${FULL_APPCAST}" "${LIVE_APPCAST}" "${EXPECTED_URL}" <<'PYXML'
import pathlib
import sys
import xml.etree.ElementTree as ET

tag, dmg, generated, full, live, expected_url = sys.argv[1:]
namespace = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"

def metadata(path):
    item = ET.parse(path).find("./channel/item")
    if item is None:
        raise ValueError("appcast has no release item")
    build = item.findtext(namespace + "version")
    version = item.findtext(namespace + "shortVersionString")
    enclosure = item.find("enclosure")
    if not build or not build.isdecimal() or enclosure is None:
        raise ValueError("appcast has invalid release metadata")
    return int(build), version, enclosure.attrib

try:
    expected = metadata(generated)
    actual = metadata(full)
    if actual != expected:
        raise ValueError("root appcast release metadata differs from generated item")
    attrs = expected[2]
    if attrs.get("url") != expected_url:
        raise ValueError("appcast enclosure URL does not match release tag")
    if expected[1] != tag[1:]:
        raise ValueError("appcast version does not match release tag")
    if int(attrs.get("length", "0")) != pathlib.Path(dmg).stat().st_size:
        raise ValueError("appcast enclosure length does not match DMG")
    if not attrs.get(namespace + "edSignature"):
        raise ValueError("appcast enclosure has no EdDSA signature")
    if pathlib.Path(live).exists():
        published = metadata(live)
        if published[0] > expected[0]:
            raise ValueError("refusing to replace a newer live build")
        if published[0] == expected[0] and published != expected:
            raise ValueError("live build already exists with different release metadata")
except (ET.ParseError, ValueError, OSError) as error:
    sys.exit("publish: " + str(error))
PYXML

(
  cd "${OUTPUT_DIR}"
  shasum -a 256 -c "$(basename "${SHA_PATH}")"
)
xcrun stapler validate "${DMG_PATH}"
/usr/sbin/spctl --assess --type open --context context:primary-signature --verbose=2 "${DMG_PATH}"

# Publish immutable artifacts first. A tag may be retried with the exact same bytes, but it
# may never be repointed at a different DMG.
EXISTING_DMG="${VERIFY_DIR}/existing-Responsay.dmg"
if ! EXISTING_STATUS="$(curl -sS -o "${EXISTING_DMG}" -w '%{http_code}' "${EXPECTED_URL}")"; then
  fail "could not determine whether ${EXPECTED_URL} already exists"
fi
case "${EXISTING_STATUS}" in
  200)
    EXISTING_SHA="$(shasum -a 256 "${EXISTING_DMG}" | awk '{print $1}')"
    [[ "${EXISTING_SHA}" == "$(awk '{print $1}' "${SHA_PATH}")" ]] ||
      fail "${TAG} already exists with different bytes"
    printf 'publish: immutable %s already matches; keeping it.\n' "${TAG}"
    ;;
  404)
    [[ "${PHASE}" == artifacts ]] || fail "immutable DMG is missing; run artifacts before activating"
    unlink "${EXISTING_DMG}"
    put_object "releases/${TAG}/Responsay.dmg" "${DMG_PATH}" \
      "application/x-apple-diskimage" "public, max-age=31536000, immutable"
    ;;
  *)
    fail "unexpected HTTP ${EXISTING_STATUS} while checking ${EXPECTED_URL}"
    ;;
esac

# A prior attempt may have uploaded the DMG but failed before its checksum. Repair only
# a missing checksum, never overwrite conflicting versioned metadata.
VERSIONED_SHA="${VERIFY_DIR}/versioned.sha256"
if ! SHA_STATUS="$(curl -sS -o "${VERSIONED_SHA}" -w '%{http_code}' "${EXPECTED_URL}.sha256")"; then
  fail "could not read the versioned checksum"
fi
case "${SHA_STATUS}" in
  200) cmp "${SHA_PATH}" "${VERSIONED_SHA}" >/dev/null || fail "versioned checksum differs" ;;
  404)
    [[ "${PHASE}" == artifacts ]] || fail "immutable checksum is missing; run artifacts before activating"
    put_object "releases/${TAG}/Responsay.dmg.sha256" "${SHA_PATH}" \
      "text/plain; charset=utf-8" "public, max-age=31536000, immutable"
    ;;
  *) fail "unexpected HTTP ${SHA_STATUS} while checking versioned checksum" ;;
esac
curl -fsSL "${EXPECTED_URL}.sha256" -o "${VERSIONED_SHA}"
cmp "${SHA_PATH}" "${VERSIONED_SHA}" >/dev/null || fail "downloaded versioned checksum differs"

DOWNLOADED_DMG="${VERIFY_DIR}/Responsay.dmg"
curl -fsSL "${EXPECTED_URL}" -o "${DOWNLOADED_DMG}"
EXPECTED_SHA="$(awk '{print $1}' "${SHA_PATH}")"
DOWNLOADED_SHA="$(shasum -a 256 "${DOWNLOADED_DMG}" | awk '{print $1}')"
[[ "${DOWNLOADED_SHA}" == "${EXPECTED_SHA}" ]] || fail "downloaded versioned DMG hash does not match"
xcrun stapler validate "${DOWNLOADED_DMG}"
/usr/sbin/spctl --assess --type open --context context:primary-signature --verbose=2 "${DOWNLOADED_DMG}"

if [[ "${PHASE}" == artifacts ]]; then
  printf 'publish: immutable %s verified; stable downloads and feeds are unchanged.\n' "${TAG}"
  exit 0
fi

# Refresh the stable manual-download objects only after the immutable artifact is proven.
put_object "Responsay.dmg" "${DMG_PATH}" \
  "application/x-apple-diskimage" "public, max-age=300, must-revalidate"
put_object "Responsay.dmg.sha256" "${SHA_PATH}" \
  "text/plain; charset=utf-8" "public, max-age=300, must-revalidate"

# The feed is the release switch and must always be published last.
put_object "appcast.xml" "${FULL_APPCAST}" \
  "application/xml; charset=utf-8" "public, max-age=300, must-revalidate"

DOWNLOADED_APPCAST="${VERIFY_DIR}/appcast.xml"
curl -fsSL "${PUBLIC_BASE_URL}/appcast.xml?published=${TAG}" -o "${DOWNLOADED_APPCAST}"
cmp "${FULL_APPCAST}" "${DOWNLOADED_APPCAST}" >/dev/null || fail "published appcast does not match the repository"

printf 'publish: %s is live at %s\n' "${TAG}" "${EXPECTED_URL}"
printf 'publish: Sparkle feed is live at %s/appcast.xml\n' "${PUBLIC_BASE_URL}"
