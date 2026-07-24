#!/usr/bin/env bash
# Privacy regression net. The debug diagnostics feed and its clipboard
# export (DiagnosticExporter) must never carry user raw text: every Diag.{tts,asr,llm}(…)
# call must log descriptors (model / engine / tone / char-count), never the intent /
# question / transcript itself. Delegates to the unit-tested scanner in
# scripts/diag-privacy-guard.mjs (see scripts/diag-privacy-guard.test.mjs).
set -euo pipefail
cd "$(dirname "$0")/../.."
exec node scripts/diag-privacy-guard.mjs
