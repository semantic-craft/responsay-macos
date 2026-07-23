import Foundation

/// Fetches/parses a provider's live model list (`GET <base>/models`) so the
/// Settings model field can be filled from what the provider currently offers.
/// Pure/Foundation — the network call + UI live in macOS.
///
/// Mirrors openless `commands/providers.rs`: OpenAI-compatible `{data:[{id}]}`
/// and Google `{models:[{name, supportedGenerationMethods}]}`.
public enum ProviderModelList {
    /// ASR/transcription id keywords; used to narrow the list on the ASR card.
    private static let asrKeywords = ["asr", "transcribe", "whisper", "fun-asr", "stt"]

    /// Build the `…/models` URL from a base or chat-completions URL.
    public static func modelsURL(base: String) -> String {
        var trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        if trimmed.hasSuffix("/models") { return trimmed }
        let chat = "/chat/completions"
        if trimmed.hasSuffix(chat) { return String(trimmed.dropLast(chat.count)) + "/models" }
        return trimmed + "/models"
    }

    /// Only the NATIVE Google endpoint (`/v1beta`) returns the `{models:[{name}]}` shape with
    /// `x-goog-api-key`. Our Gemini preset uses the OpenAI-COMPAT base (`/v1beta/openai/`), which
    /// returns the standard `{data:[{id}]}` shape with Bearer — so it must NOT be treated as
    /// Gemini-native, or Fetch-models parses the wrong key and returns nothing.
    public static func isGeminiBase(_ base: String) -> Bool {
        base.contains("generativelanguage.googleapis.com") && !base.contains("/openai")
    }

    /// Parse model ids from a `/models` response. Returns sorted, de-duplicated ids,
    /// or `[]` on any malformed body. For Gemini, models that explicitly do NOT
    /// support `generateContent` (embeddings/TTS/image) are dropped; a model that
    /// omits the field is kept (preview models sometimes do).
    public static func parse(_ data: Data, isGemini: Bool) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        let ids: [String]
        if isGemini {
            let models = root["models"] as? [[String: Any]] ?? []
            ids = models.compactMap { item in
                if let methods = item["supportedGenerationMethods"] as? [String],
                   !methods.contains("generateContent") {
                    return nil
                }
                guard let name = item["name"] as? String else { return nil }
                let stripped = name.hasPrefix("models/") ? String(name.dropFirst("models/".count)) : name
                let value = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
        } else {
            let array = root["data"] as? [[String: Any]] ?? []
            ids = array.compactMap { item in
                guard let raw = (item["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !raw.isEmpty else { return nil }
                // Gemini's openai-compat list may still carry a `models/` prefix on the id.
                return raw.hasPrefix("models/") ? String(raw.dropFirst("models/".count)) : raw
            }
        }
        return Array(Set(ids)).sorted()
    }

    /// Whether a model id advertises ASR/transcription via a known keyword
    /// (`asr`/`transcribe`/`whisper`/`fun-asr`/`stt`).
    public static func looksLikeASR(_ id: String) -> Bool {
        let lower = id.lowercased()
        return asrKeywords.contains { lower.contains($0) }
    }

    /// Narrow a model list to ASR/transcription ids by keyword. Falls back to the
    /// full list when nothing matches (e.g. Gemini's ASR is a general model), so a
    /// provider whose ids don't advertise ASR isn't reduced to nothing.
    public static func asrModels(from ids: [String]) -> [String] {
        let filtered = ids.filter(looksLikeASR)
        return filtered.isEmpty ? ids : filtered
    }
}
