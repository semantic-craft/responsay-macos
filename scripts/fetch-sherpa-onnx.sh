#!/usr/bin/env bash
# Fetch the prebuilt sherpa-onnx macOS libraries into Vendor/ as two xcframeworks:
#   Vendor/sherpa-onnx.xcframework   (sherpa-onnx merged static lib)
#   Vendor/onnxruntime.xcframework   (onnxruntime static lib, built from the dev tarball)
#
# Why a script instead of committing the binaries: together they are ~175MB and
# would bloat git history. They are NOT downloaded by end users — they link into
# the shipped .app at build time. Developers run this once before building.
#
# Pinned to a known release + sha256 so every machine gets the same binaries.
set -euo pipefail

VERSION="v1.13.2"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="${ROOT}/Vendor"
STAMP="${VENDOR}/.sherpa-onnx.version"

XCF_ASSET="sherpa-onnx-${VERSION}-macos-xcframework-static.tar.bz2"
XCF_SHA="8756afb64ef7a1d612040c323e6f2cf707f90e703395413c79c572e37eddd65e"

ORT_ASSET="sherpa-onnx-${VERSION}-osx-universal2-static.tar.bz2"
ORT_SHA="11c56c6577812e30ad3422a826a07f2a4a04b20d926af45b17e7dd9af99dd035"

base_url="https://github.com/k2-fsa/sherpa-onnx/releases/download/${VERSION}"

has_headers_path() {
  /usr/libexec/PlistBuddy -c "Print :AvailableLibraries:0:HeadersPath" "$1/Info.plist" >/dev/null 2>&1
}

if [[ -d "${VENDOR}/sherpa-onnx.xcframework" \
      && -d "${VENDOR}/onnxruntime.xcframework" \
      && "$(cat "${STAMP}" 2>/dev/null || true)" == "${VERSION}" ]] \
      && has_headers_path "${VENDOR}/sherpa-onnx.xcframework" \
      && has_headers_path "${VENDOR}/onnxruntime.xcframework"; then
  echo "✓ sherpa-onnx ${VERSION} already vendored at ${VENDOR}"
  exit 0
fi

fetch_verify() { # asset sha -> downloads into $TMP and checks sha256
  local asset="$1" sha="$2"
  echo "↓ downloading ${asset} …"
  curl -fL --retry 3 -o "${TMP}/${asset}" "${base_url}/${asset}"
  local actual; actual="$(shasum -a 256 "${TMP}/${asset}" | awk '{print $1}')"
  if [[ "${actual}" != "${sha}" ]]; then
    echo "✗ sha256 mismatch for ${asset}" >&2
    echo "  expected ${sha}" >&2
    echo "  actual   ${actual}" >&2
    exit 1
  fi
}

mkdir -p "${VENDOR}"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

# 1. sherpa-onnx.xcframework (ships as-is)
fetch_verify "${XCF_ASSET}" "${XCF_SHA}"
tar xjf "${TMP}/${XCF_ASSET}" -C "${TMP}"
SHERPA_XCF="${TMP}/sherpa-onnx-${VERSION}-macos-xcframework-static/sherpa-onnx.xcframework"
rm -rf "${VENDOR}/sherpa-onnx.xcframework"
xcodebuild -create-xcframework \
  -library "${SHERPA_XCF}/macos-arm64_x86_64/libsherpa-onnx.a" \
  -headers "${SHERPA_XCF}/macos-arm64_x86_64/Headers" \
  -output "${VENDOR}/sherpa-onnx.xcframework" >/dev/null

# 2. onnxruntime.xcframework (built from the universal2 static dev tarball)
fetch_verify "${ORT_ASSET}" "${ORT_SHA}"
tar xjf "${TMP}/${ORT_ASSET}" -C "${TMP}"
ORT_LIB="${TMP}/sherpa-onnx-${VERSION}-osx-universal2-static/lib/libonnxruntime.a"
mkdir -p "${TMP}/onnxruntime-empty-headers"
rm -rf "${VENDOR}/onnxruntime.xcframework"
xcodebuild -create-xcframework \
  -library "${ORT_LIB}" \
  -headers "${TMP}/onnxruntime-empty-headers" \
  -output "${VENDOR}/onnxruntime.xcframework" >/dev/null

echo "${VERSION}" > "${STAMP}"
echo "✓ vendored sherpa-onnx + onnxruntime ${VERSION} → ${VENDOR}"
