#!/usr/bin/env bash
# Architecture regression net: line cap (+ grandfather), print ban, fatalError-in-audio
# ban, and retired-BYOK-seam reference ban. Delegates to the unit-tested scanner in
# scripts/architecture-lint.mjs (see scripts/architecture-lint.test.mjs).
set -euo pipefail
cd "$(dirname "$0")/../.."
exec node scripts/architecture-lint.mjs
