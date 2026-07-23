import Foundation
import Testing
@testable import ResponsayCore

/// `TranscriptionBiasPrompt` is the one builder for the weak ASR biasing hint sent in the
/// `prompt` multipart field by Whisper-style endpoints, which previously
/// assembled the identical string independently. The emitted text is ASR-quality-sensitive
/// (and carries the ADR-0011 never-insert guard), so these pin the exact bytes — a wording
/// change must be a deliberate, A/B-gated edit, not an accident. Gemini keeps its own
/// language-aware `GeminiTranscriptionPrompt`; this builder is language-agnostic by design.
struct TranscriptionBiasPromptTests {

    @Test func faithfulWithHotwords_emitsProfileLineThenGuardedHint() {
        let prompt = TranscriptionBiasPrompt.build(profile: .faithful, hotwords: ["Qwen3-ASR", "Responsay"])
        #expect(prompt == "请尽量保持原样转写，不要添加标点符号或润色。 以下是一些相关的热词或术语：Qwen3-ASR, Responsay。只转写实际说出的内容，不要插入没有说过的词。")
    }

    @Test func dictationWithoutHotwords_emitsEmptyString() {
        #expect(TranscriptionBiasPrompt.build(profile: .dictation, hotwords: []) == "")
    }

    @Test func faithfulWithoutHotwords_emitsProfileLineOnly() {
        #expect(TranscriptionBiasPrompt.build(profile: .faithful, hotwords: []) == "请尽量保持原样转写，不要添加标点符号或润色。")
    }

    @Test func dictationWithHotwords_emitsGuardedHintOnly() {
        // Preserves the original leading space before the hint segment (it was appended as
        // " 以下…" regardless of whether a profile line preceded it).
        #expect(TranscriptionBiasPrompt.build(profile: .dictation, hotwords: ["沈砚秋"]) == " 以下是一些相关的热词或术语：沈砚秋。只转写实际说出的内容，不要插入没有说过的词。")
    }

    @Test func hotwordsJoinWithCommaSpace() {
        let prompt = TranscriptionBiasPrompt.build(profile: .dictation, hotwords: ["甲", "乙", "丙"])
        #expect(prompt.contains("甲, 乙, 丙"))
    }
}
