import Foundation

/// Best-effort, on-device punctuation restoration for an unpunctuated transcript — e.g. the raw
/// output of an offline ASR model (SenseVoice / Qwen3-ASR / FireRedASR2) that emits no punctuation.
///
/// Used by the 如实输入 (faithful / raw) path so verbatim dictation can still get punctuation
/// WITHOUT sending the text through an LLM (no rewrite, no network). Distinct from `TextPolishAPI`,
/// which is the heavier LLM tidy that also removes fillers and may lightly reword.
///
/// Never throws — punctuation is best-effort; an unavailable or not-applicable engine returns the
/// text unchanged.
public protocol TextPunctuator: Sendable {
    func punctuate(_ text: String) async -> String
}
