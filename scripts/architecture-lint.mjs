#!/usr/bin/env node
// Architecture regression net. Mechanical, grep-style rules that prevent NEW
// violations of the project's structure conventions; existing debt is grandfathered so
// the lint is green today and only fails on regressions. Rules:
//   1. line cap   — no NEW Swift file > MAX_LINES (existing offenders grandfathered;
//                   completed split targets are removed from the list as they land).
//   2. print ban  — no `print(` in macOS production sources; use Logger, so diagnostics
//                   stay redactable and never reach stdout.
//   3. fatalError — no `fatalError(` in the sherpa audio wrappers; a malformed model or
//                   device change must surface as a typed error, not kill the app.
//   4. backend    — no `BackendClientMetadata` / `keyHeaderProvider` in macOS; the
//                   launch-time header seam was removed when the app went BYOK.
//   5. retired     — no retired Node-backend stack (HTTP*API / BackendConfiguration /
//                   BackendHealthStatus / localhost:8787 / backendURL) in production
//                   sources. Responsay is app-direct/BYOK: requests go straight from the
//                   app to the provider the user configured, with no Responsay backend.
//
// NOT enforced: "one type per file". A reliable check needs a real Swift parser (regex
// false-positives on value-type companions, nested types, and extensions, of which this
// codebase has many legitimately), so it is intentionally omitted rather than shipped noisy.
//
// Pure helpers are unit-tested in architecture-lint.test.mjs; run directly
// (`node scripts/architecture-lint.mjs`) to scan the tree and exit non-zero on a violation.
// `scripts/lint/no-architecture-regressions.sh` is the lint-suite entry.

import { readFileSync, readdirSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join, relative } from "node:path";

export const MAX_LINES = 400;

/// Files that still exceed MAX_LINES today. Frozen here so the lint passes on the
/// current tree; the rule's value is blocking NEW giant files. Remove entries as
/// they are split. Line counts are the values at the time this list was frozen.
export const LINE_CAP_GRANDFATHER = [
  "macOS/Speech/SherpaOnnx/SherpaOnnxOfflineASR.swift", // 507, vendored sherpa wrapper
  "macOS/Speech/SherpaOnnx/SherpaOnnxTTS.swift", // 428, vendored sherpa wrapper
  "macOS/MainWindow/LegalSkillsScreen.swift", // 439
  "macOS/App/CaptureController.swift", // 418, regressed past the cap after an earlier split
  "macOS/Hotkey/NativeHotkeyEventTap.swift", // 411
  "macOS/Capsule/CapsulePanel.swift", // 406
  "Packages/ResponsayCore/Sources/ResponsaySpeech/CloudQwenSpeechCaptureService.swift", // 450
  "Packages/ResponsayCore/Sources/ResponsayCore/Hotword/HotwordHardMatch.swift", // 435
  "Packages/ResponsayCore/Sources/ResponsayCore/Capture/QuickCaptureViewModel.swift", // 428, regressed past the cap after an earlier split
  "Packages/ResponsayCore/Sources/ResponsayCore/Capture/CaptureTransformer.swift", // 411
];

export const PRINT_RE = /(?<!\.)\bprint\(/;
export const FATAL_ERROR_RE = /\bfatalError\(/;
export const BACKEND_REF_RE = /\b(?:BackendClientMetadata|keyHeaderProvider)\b/;

/// The retired Node-backend client stack. These types relayed through `localhost:8787`;
/// the app is now app-direct (BYOK), so they must not reappear in production sources.
/// `BackendClientMetadata` is intentionally NOT here — it is a live shared request-header
/// helper (X-Client-Id / User-Agent) still used by legal request shapes; its separate
/// macOS ban lives in BACKEND_REF_RE.
export const RETIRED_BACKEND_NAMES = [
  "HTTPCoachAPI", "HTTPTranscriptionAPI", "HTTPModelManagerAPI", "HTTPRewriteActionAPI",
  "HTTPTextPolishAPI", "HTTPTextRewriteAPI", "HTTPTextTranslationAPI", "HTTPBackendHealthAPI",
  "BackendConfiguration", "BackendHealthStatus", "backendURL",
  // Backend-shaped orphans and the retired transform-stream insertion path.
  "StreamingTextTransformClient", "HTTPLegalSkillExecutorAPI",
  "DirectStreamingTransformClient", "StreamingTransformPromptBuilder", "TextTransformRequest",
  "StreamingInsertionController", "StreamingInsertSettings", "StreamingTransformOutcome",
  "StreamingInsertBuffer", "SSELineParser",
];
export const RETIRED_BACKEND_RE = new RegExp(
  `\\b(?:${RETIRED_BACKEND_NAMES.join("|")})\\b|localhost:8787`,
);

export function overLineCap(path, lineCount) {
  return lineCount > MAX_LINES && !LINE_CAP_GRANDFATHER.includes(path);
}

/// Line count matching `wc -l` semantics for newline-terminated files: the empty string
/// after a trailing newline is not a line. Counting it would make a 400-line file read as
/// 401 and fail the advertised cap.
export function countLines(source) {
  const parts = source.split("\n");
  return parts[parts.length - 1] === "" ? parts.length - 1 : parts.length;
}

/// 1-based line numbers of non-`//`-comment lines that match `regex`.
export function scanForPattern(source, regex) {
  const out = [];
  source.split("\n").forEach((line, i) => {
    if (line.trim().startsWith("//")) return;
    if (regex.test(line)) out.push(i + 1);
  });
  return out;
}

// ---- CLI ---------------------------------------------------------------------------

function swiftFilesUnder(root) {
  const out = [];
  const walk = (dir) => {
    for (const name of readdirSync(dir)) {
      if (name === ".build") continue;
      const p = join(dir, name);
      const st = statSync(p);
      if (st.isDirectory()) walk(p);
      else if (name.endsWith(".swift")) out.push(p);
    }
  };
  walk(root);
  return out;
}

function main() {
  const here = dirname(fileURLToPath(import.meta.url));
  const repoRoot = join(here, "..");
  const rel = (p) => relative(repoRoot, p);
  const findings = [];

  // Rule 1: line cap over macOS + ResponsayCore sources.
  const lineCapRoots = ["macOS", "Packages/ResponsayCore/Sources"].map((d) => join(repoRoot, d));
  for (const root of lineCapRoots) {
    for (const file of swiftFilesUnder(root)) {
      const lines = countLines(readFileSync(file, "utf8"));
      if (overLineCap(rel(file), lines)) {
        findings.push(`${rel(file)}: ${lines} lines > ${MAX_LINES} (split it, or add it to LINE_CAP_GRANDFATHER with a reason)`);
      }
    }
  }

  // Rules 2–4: pattern bans, each scoped to where the concern lives.
  const macOSFiles = swiftFilesUnder(join(repoRoot, "macOS"));
  for (const file of macOSFiles) {
    const path = rel(file);
    const source = readFileSync(file, "utf8");
    for (const ln of scanForPattern(source, PRINT_RE)) {
      findings.push(`${path}:${ln}: print( in production — use Logger`);
    }
    for (const ln of scanForPattern(source, BACKEND_REF_RE)) {
      findings.push(`${path}:${ln}: BackendClientMetadata/keyHeaderProvider — the BYOK header seam was removed`);
    }
    if (path.startsWith("macOS/Speech/")) {
      for (const ln of scanForPattern(source, FATAL_ERROR_RE)) {
        findings.push(`${path}:${ln}: fatalError( in an audio/ASR path — throw a typed error`);
      }
    }
  }

  // Rule 5: retired Node-backend stack ban over production sources (macOS + Core).
  // Tests are excluded — they may still stub `localhost` transport for kept clients.
  const retiredRoots = ["macOS", "Packages/ResponsayCore/Sources"].map((d) =>
    join(repoRoot, d),
  );
  for (const root of retiredRoots) {
    for (const file of swiftFilesUnder(root)) {
      const path = rel(file);
      for (const ln of scanForPattern(readFileSync(file, "utf8"), RETIRED_BACKEND_RE)) {
        findings.push(
          `${path}:${ln}: retired Node-backend reference — the app is app-direct/BYOK`,
        );
      }
    }
  }

  if (findings.length > 0) {
    console.error("architecture-lint: FAIL");
    for (const f of findings) console.error("  " + f);
    process.exit(1);
  }
  console.log("architecture-lint: OK");
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  main();
}
