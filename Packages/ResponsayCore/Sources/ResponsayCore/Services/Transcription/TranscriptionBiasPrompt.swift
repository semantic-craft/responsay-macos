import Foundation

/// The weak ASR biasing hint for Whisper-style transcription endpoints that accept a
/// free-text `prompt` field. It nudges recognition toward the
/// capture profile (faithful → don't normalize) and the user's hotwords, while carrying the
/// ADR-0011 never-insert guard so it can only bias, never inject unspoken words.
///
/// This is the single source for clients that support the hint.
/// It is language-agnostic by design (the endpoints take a separate `language` field). Gemini
/// is a multimodal LLM, not an ASR endpoint, so it keeps its own language-aware
/// `GeminiTranscriptionPrompt`. Hard-match enforcement is a separate post-pass (ADR-0011).
///
/// Pure + deterministic so the contract can be pinned without a network.
enum TranscriptionBiasPrompt {
    static func build(profile: SpeechCaptureProfile, hotwords: [String]) -> String {
        let joined = hotwords.joined(separator: ", ")
        var prompt = ""
        if profile == .faithful {
            prompt += "请尽量保持原样转写，不要添加标点符号或润色。"
        }
        if !joined.isEmpty {
            // ADR-0011: the weak hint must keep the never-insert guard — bias
            // recognition toward the terms, never inject unspoken words.
            prompt += " 以下是一些相关的热词或术语：\(joined)。只转写实际说出的内容，不要插入没有说过的词。"
        }
        return prompt
    }
}
