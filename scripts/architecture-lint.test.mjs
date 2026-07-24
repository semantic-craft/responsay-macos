import test from "node:test";
import assert from "node:assert/strict";
import {
  MAX_LINES,
  LINE_CAP_GRANDFATHER,
  overLineCap,
  scanForPattern,
  PRINT_RE,
  FATAL_ERROR_RE,
  BACKEND_REF_RE,
  RETIRED_BACKEND_RE,
} from "./architecture-lint.mjs";

// Architecture regression net. Mechanical rules only (line cap + grandfather,
// print ban, fatalError-in-audio ban, backend-reference ban). The pure helpers are
// tested here; the CLI walks the tree and exits non-zero on a violation.

test("overLineCap flags a new >400-line file but not a grandfathered one", () => {
  assert.equal(overLineCap("macOS/New/Huge.swift", MAX_LINES + 1), true);
  assert.equal(overLineCap("macOS/New/Huge.swift", MAX_LINES), false);
  const grand = LINE_CAP_GRANDFATHER[0];
  assert.equal(overLineCap(grand, 9999), false, "grandfathered file must be exempt");
});

test("completed split targets are no longer line-cap grandfathered", () => {
  for (const path of [
    "macOS/Settings/SettingsView.swift",
  ]) {
    assert.equal(overLineCap(path, MAX_LINES + 1), true, `${path} should obey the 400-line cap`);
  }
});

test("PRINT_RE matches a bare print( but not a method .print( call", () => {
  assert.deepEqual(scanForPattern(`        print("hi")`, PRINT_RE), [1]);
  assert.deepEqual(scanForPattern(`        logger.print("hi")`, PRINT_RE), []);
});

test("scanForPattern skips // comment lines", () => {
  const src = [`// print("not real")`, `   /// fatalError("doc")`, `print("real")`].join("\n");
  assert.deepEqual(scanForPattern(src, PRINT_RE), [3]);
});

test("FATAL_ERROR_RE matches fatalError( but not a comment mention", () => {
  assert.deepEqual(scanForPattern(`      fatalError("boom")`, FATAL_ERROR_RE), [1]);
  assert.deepEqual(scanForPattern(`// no more fatalError() here`, FATAL_ERROR_RE), []);
});

test("BACKEND_REF_RE matches the retired seam identifiers, comments excluded", () => {
  assert.deepEqual(
    scanForPattern(`        BackendClientMetadata.keyHeaderProvider = {`, BACKEND_REF_RE),
    [1]);
  assert.deepEqual(
    scanForPattern(`// 332: no launch-time BYOK header install`, BACKEND_REF_RE),
    [], "the 332 explanatory comment must not trip the rule");
});

test("RETIRED_BACKEND_RE flags the retired Node-backend stack but spares live types", () => {
  // The retired stack must be caught.
  for (const dead of [
    `        let api = HTTPCoachAPI(baseURL: url)`,
    `        HTTPTranscriptionAPI(baseURL: url).transcribe(req)`,
    `    baseURL: BackendConfiguration.defaultBaseURL`,
    `        let s: BackendHealthStatus? = nil`,
    `        let u = URL(string: "http://localhost:8787")!`,
    `        self.backendURL = url`,
  ]) {
    assert.deepEqual(scanForPattern(dead, RETIRED_BACKEND_RE), [1], `should flag: ${dead}`);
  }
  // The backend-shaped orphans and transform-stream insertion path are also banned.
  for (const dead of [
    `        let c = StreamingTextTransformClient(baseURL: url)`,
    `        let api = HTTPLegalSkillExecutorAPI(baseURL: url)`,
    `        let c = DirectStreamingTransformClient(endpoint: endpoint)`,
    `    func run(_ request: TextTransformRequest) async -> Outcome`,
    `        let c = StreamingInsertionController(targetProvider: { target })`,
    `        let enabled = StreamingInsertSettings.isEnabled`,
    `        let parser = SSELineParser()`,
  ]) {
    assert.deepEqual(scanForPattern(dead, RETIRED_BACKEND_RE), [1], `should flag: ${dead}`);
  }
  // Live / kept types must NOT be flagged — the deletion is surgical.
  for (const live of [
    `    private let api: any CoachAPI`,
    `    func transcribe(_ r: Request) -> TranscriptionAPI`,
    `        BackendClientMetadata.apply(to: &request)`,
    `        let c = DirectStreamingChatClient(endpoint: endpoint)`,
    `    func streamTranscription(audio: Data) -> AsyncThrowingStream<TextStreamEvent, Error>`,
    `public protocol LegalSkillExecutorAPI: Sendable {`,
    `// the old localhost:8787 relay is retired`,
  ]) {
    assert.deepEqual(scanForPattern(live, RETIRED_BACKEND_RE), [], `must not flag: ${live}`);
  }
});
