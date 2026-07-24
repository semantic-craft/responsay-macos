#!/usr/bin/env bash
# Guard against rename drift between the two tracked sources of brand identity:
#   - Packages/ResponsayCore/.../Brand/AppBrand.swift  (Swift constants used at runtime)
#   - project.yml                                       (XcodeGen source of truth; .xcodeproj/Info.plist are generated)
# These two must agree: project.yml is tracked and .xcodeproj is regenerated from it via
# `xcodegen generate`, so nothing else asserts that the Swift constants still match the
# generated app identity. A legacy identity leaking into project.yml is also a failure.
set -euo pipefail
cd "$(dirname "$0")/../.."

APPBRAND="Packages/ResponsayCore/Sources/ResponsayCore/Brand/AppBrand.swift"
PROJECT="project.yml"
fail=0

value() { # extract the string literal assigned to a given AppBrand constant
  grep -E "let $1 = \"" "$APPBRAND" | sed -E 's/.*= "([^"]*)".*/\1/' | head -1
}

require_in_project() { # the AppBrand value must appear in project.yml
  local label="$1" val="$2"
  if [[ -z "$val" ]]; then echo "FAIL: AppBrand.$label not found"; fail=1; return; fi
  if grep -qF -- "$val" "$PROJECT"; then
    echo "ok: $label = $val"
  else
    echo "DRIFT: AppBrand.$label = '$val' is absent from project.yml"; fail=1
  fi
}

# iOSBundleIdentifier is intentionally not checked: this repository ships macOS only, so
# project.yml has no iOS target to agree with. AppBrand keeps the constant for ResponsayCore.
require_in_project macOSBundleIdentifier "$(value macOSBundleIdentifier)"
require_in_project urlScheme             "$(value urlScheme)"
require_in_project displayName           "$(value displayName)"

# Legacy identities must NEVER appear in the generated app identity (they exist only for
# local cleanup scripts, the rename inventory, and tests).
for label in legacyIOSBundleIdentifier legacyMacOSBundleIdentifier legacyDisplayName; do
  val="$(value "$label")"
  if [[ -n "$val" ]] && grep -qF -- "$val" "$PROJECT"; then
    echo "LEAK: legacy identity AppBrand.$label = '$val' appears in project.yml"; fail=1
  fi
done

if [[ "$fail" == "1" ]]; then
  echo "brand-identity-consistency: FAIL"
  exit 1
fi
echo "brand-identity-consistency: OK"
