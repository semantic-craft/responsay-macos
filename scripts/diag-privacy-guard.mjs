#!/usr/bin/env node
// Diagnostics privacy guard. The debug diagnostics feed and its
// clipboard export (`DiagnosticExporter`) must never carry user raw text. The redaction
// lives at the `Diag.{tts,asr,llm}(…)` call sites (fields must be descriptors — model /
// engine / tone / char-count — never the intent / question / transcript itself). This
// scanner is the regression net: it flags a banned key used *inside a Diag call* and is
// blind to identical keys in unrelated dictionaries (e.g. a network request body), so it
// does not false-positive on `["text": request.text]`.
//
// Pure core (`scanDiagRawText`) is unit-tested in diag-privacy-guard.test.mjs; run
// directly (`node scripts/diag-privacy-guard.mjs`) to scan the macOS sources and exit
// non-zero on any violation. `scripts/lint/no-diag-raw-text.sh` is the lint-suite entry.

import { readFileSync, readdirSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join, relative } from "node:path";

/// Field keys that would carry user content. Exact-match only (quote-key-quote), so the
/// redacted forms (`intentChars`, `questionChars`) and longer names (`userIntent`,
/// `context`) are intentionally NOT flagged.
export const BANNED_KEYS = [
  "intent",
  "question",
  "text",
  "transcript",
  "sentence",
  "selectedText",
  "selection",
  "prompt",
  "original",
  "utterance",
];

const DIAG_CALL = /\bDiag\.(?:tts|asr|llm)\s*\(/;

/// Net paren delta of a line, ignoring parens inside double-quoted string literals.
function parenDelta(line) {
  let depth = 0;
  let inString = false;
  let escaped = false;
  for (const ch of line) {
    if (escaped) {
      escaped = false;
      continue;
    }
    if (ch === "\\") {
      escaped = true;
      continue;
    }
    if (ch === '"') {
      inString = !inString;
      continue;
    }
    if (inString) continue;
    if (ch === "(") depth++;
    else if (ch === ")") depth--;
  }
  return depth;
}

/// Scan Swift source text. Returns `[{line, key}]` for every banned field key that
/// appears within the argument span of a `Diag.{tts,asr,llm}(…)` call.
export function scanDiagRawText(source) {
  const lines = source.split("\n");
  const keyRe = new RegExp(`"(${BANNED_KEYS.join("|")})"\\s*:`, "g");
  const violations = [];
  let inDiag = false;
  let depth = 0;

  const scanForKeys = (fragment, lineNo) => {
    keyRe.lastIndex = 0;
    let m;
    while ((m = keyRe.exec(fragment)) !== null) {
      violations.push({ line: lineNo, key: m[1] });
    }
  };

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const lineNo = i + 1;
    if (!inDiag) {
      const start = DIAG_CALL.exec(line);
      if (!start) continue;
      const fragment = line.slice(start.index); // from `Diag.x(` onward
      scanForKeys(fragment, lineNo);
      depth = parenDelta(fragment);
      inDiag = depth > 0; // false → single-line call already closed
    } else {
      scanForKeys(line, lineNo);
      depth += parenDelta(line);
      if (depth <= 0) inDiag = false;
    }
  }
  return violations;
}

// ---- CLI ---------------------------------------------------------------------------

function swiftFilesUnder(root) {
  const out = [];
  const walk = (dir) => {
    for (const name of readdirSync(dir)) {
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
  const scanRoot = join(repoRoot, "macOS"); // all `Diag.` call sites live here
  const findings = [];
  for (const file of swiftFilesUnder(scanRoot)) {
    const rel = relative(repoRoot, file);
    for (const v of scanDiagRawText(readFileSync(file, "utf8"))) {
      findings.push(`${rel}:${v.line}: Diag field "${v.key}" carries user raw text`);
    }
  }
  if (findings.length > 0) {
    console.error("diag-privacy-guard: FAIL — diagnostics must not log user text");
    for (const f of findings) console.error("  " + f);
    console.error(
      "  Fix: log a descriptor (e.g. \"intentChars\": String(intent.count)), not the content."
    );
    process.exit(1);
  }
  console.log("diag-privacy-guard: OK");
}

// Run only when invoked directly, not when imported by the test.
if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  main();
}
