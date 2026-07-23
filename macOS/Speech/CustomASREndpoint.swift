import Foundation

/// Resolves the 自定义 (OpenAI 兼容) ASR engine's endpoint + model from the
/// credential card's keys (issue 320). Until 2026-06-11 this engine read its
/// own `customASRBaseURL`/`customASRModel` pair from a「高级」disclosure while
/// the credential card showed Base URL / Model fields that the runtime never
/// read — two surfaces, one silently dead. The card keys are now the single
/// source; the legacy pair is still read as a migration fallback.
enum CustomASREndpoint {
    static let providerID = "custom"

    /// Base URL in OpenAI-compatible form (…/v1); the client appends
    /// `audio/transcriptions` itself — the old「高级」placeholder that told
    /// users to paste the full /audio/transcriptions path was wrong.
    static func baseURL(defaults: UserDefaults = .standard) -> URL {
        let card = (defaults.string(forKey: "byok.asr.provider") == providerID
            ? defaults.string(forKey: "byok.asr.baseURL") : nil)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let legacy = (defaults.string(forKey: "customASRBaseURL") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = !card.isEmpty ? card : legacy
        return URL(string: raw.isEmpty ? "https://api.openai.com/v1" : raw)
            ?? URL(string: "https://api.openai.com/v1")!
    }

    static func model(defaults: UserDefaults = .standard) -> String {
        let card = (defaults.string(forKey: "byok.asr.provider") == providerID
            ? defaults.string(forKey: "byok.asr.model") : nil)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !card.isEmpty { return card }
        let legacy = (defaults.string(forKey: "customASRModel") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return legacy.isEmpty ? "whisper-1" : legacy
    }
}
