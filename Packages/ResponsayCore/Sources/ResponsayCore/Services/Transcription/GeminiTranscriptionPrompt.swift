import Foundation

/// Builds the text part that turns Gemini's multimodal `:generateContent` into a
/// transcribe-only ASR call. A bare "transcribe this" lets the LLM editorialize —
/// summarize, translate, add quotation marks, or describe the audio. The prompt
/// therefore hard-constrains it to emit ONLY the verbatim transcript, mirrors the
/// faithful-profile "don't normalize punctuation" rule the other ASR clients use,
/// and carries the hotword weak hint with the ADR-0011 never-insert guard.
///
/// Pure + deterministic so the branches can be pinned without a network.
enum GeminiTranscriptionPrompt {
    static func build(
        language: String,
        profile: SpeechCaptureProfile,
        hotwords: [String]
    ) -> String {
        let chinese = language.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased().hasPrefix("zh")
        var lines: [String] = []

        if chinese {
            lines.append("请逐字转写这段音频中的语音。只输出转写出来的文字本身，不要翻译、不要总结、不要添加任何解释、说明、时间戳或引号。如果音频里没有可识别的语音，就输出空字符串。")
            if profile == .faithful {
                lines.append("尽量保持原样转写，不要添加或规整标点符号。")
            }
            let terms = hotwords.joined(separator: "、")
            if !terms.isEmpty {
                // ADR-0011: weak hint must keep the never-insert guard — bias
                // recognition toward the terms, never inject unspoken words.
                lines.append("以下是一些可能出现的热词或术语：\(terms)。只转写实际说出的内容，不要插入没有说过的词。")
            }
        } else {
            lines.append("Transcribe the speech in this audio verbatim. Output ONLY the transcript text itself — do not translate, summarize, explain, add timestamps, or wrap it in quotation marks. If there is no intelligible speech, output an empty string.")
            if profile == .faithful {
                lines.append("Keep it as spoken; do not add or normalize punctuation.")
            }
            let terms = hotwords.joined(separator: ", ")
            if !terms.isEmpty {
                lines.append("These terms may appear: \(terms). Only transcribe what is actually said; never insert words that were not spoken.")
            }
        }
        return lines.joined(separator: "\n")
    }
}
