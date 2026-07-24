import test from "node:test";
import assert from "node:assert/strict";
import { scanDiagRawText, BANNED_KEYS } from "./diag-privacy-guard.mjs";

// Privacy regression net. A `Diag.{tts,asr,llm}(…)` diagnostic call must never
// carry a user-text field (intent / question / transcript / …). These cases pin both
// halves: it MUST flag raw-text keys inside a Diag call, and it MUST NOT flag the
// redacted replacements or unrelated (non-Diag) dictionaries like network request bodies.

test("flags a raw intent key inside a single-line Diag.llm call", () => {
  const src = `Diag.llm(.info, "express start", fields: ["intent": intent, "model": endpoint.model])`;
  const v = scanDiagRawText(src);
  assert.equal(v.length, 1);
  assert.equal(v[0].key, "intent");
  assert.equal(v[0].line, 1);
});

test("flags question even when truncated via prefix()", () => {
  const src = `Diag.llm(.error, "ask failed", fields: ["question": String(question.prefix(50)), "model": m], error: e)`;
  const v = scanDiagRawText(src);
  assert.deepEqual(v.map((x) => x.key), ["question"]);
});

test("flags a raw key in a multi-line Diag call and reports the right line", () => {
  const src = [
    `Diag.llm(.error, "x", fields: [`, // 1
    `    "transcript": t,`, //             2
    `    "model": m,`, //                  3
    `])`, //                              4
  ].join("\n");
  const v = scanDiagRawText(src);
  assert.equal(v.length, 1);
  assert.equal(v[0].key, "transcript");
  assert.equal(v[0].line, 2);
});

test("does NOT flag the redacted intentChars replacement", () => {
  const src = `Diag.llm(.info, "express start", fields: ["intentChars": String(intent.count), "model": m])`;
  assert.deepEqual(scanDiagRawText(src), []);
});

test("does NOT flag a non-Diag dictionary (network request body)", () => {
  const src = `var body: [String: Any] = ["text": request.text, "mode": request.mode]`;
  assert.deepEqual(scanDiagRawText(src), []);
});

test("does NOT flag safe descriptor-only fields", () => {
  const src = [
    `Diag.tts(.info, "synth done", fields: ["engine": engineTitle, "chunks": String(n)])`,
    `Diag.asr(.info, "capture start", fields: ["engine": e, "locale": locale.rawValue])`,
    `Diag.llm(.info, "rewrite start", fields: ["tone": tone.rawValue, "model": m])`,
  ].join("\n");
  assert.deepEqual(scanDiagRawText(src), []);
});

test("does NOT flag a banned word that is only a substring of a longer key", () => {
  // "context" contains "text"; "userIntent" contains "intent" — neither is the exact key.
  const src = `Diag.llm(.info, "x", fields: ["context": c, "userIntent": ui])`;
  assert.deepEqual(scanDiagRawText(src), []);
});

test("BANNED_KEYS covers the core user-text field names", () => {
  for (const k of ["intent", "question", "text", "transcript"]) {
    assert.ok(BANNED_KEYS.includes(k), `expected ${k} in BANNED_KEYS`);
  }
});
