import Foundation

/// Swift port of backend `buildPolishPrompt`. App-direct path (epic 238, tracer 239): the
/// polish prompt now lives on the client so the app can call the provider straight.
/// 意图成稿 (active, 2026-06-19) = turn the raw ASR transcript into the message the user meant
/// to send: remove fillers, fix punctuation, resolve self-corrections, reframe rambling phrasing,
/// auto-format spoken lists — while keeping the faithfulness floor (no invented facts/names,
/// no inflated certainty). Same source language/locale.
enum PolishPromptBuilder {
    /// 418 — `styleHint` is the active 日常办公 style pack's register prompt; the bundled
    /// `light_polish` skill is the steering backing (2026-06-16). Both are now handed to the
    /// assembler as `Options` and assembled in order *before* the output format (#491) — no more
    /// post-build `system += …` surgery — so a register nudge can never land after OUTPUT FORMAT.
    /// The JSON envelope / output format are untouched, so `PolishPlainTextFallback` is unaffected.
    static func build(text: String, styleHint: String? = nil, context: String? = nil) -> (system: String, user: String) {
        TextTransformPromptAssembler.build(
            action: .polish,
            text: text,
            input: .rawTranscript,
            output: .jsonTextChanges,
            options: .init(context: context, steering: PolishTidySkill.steeringSection(), styleHint: styleHint))
    }
}
