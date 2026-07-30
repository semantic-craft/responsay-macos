import Foundation

/// Pure URL and auth helpers for OpenAI-compatible text-generation routes. Most BYOK providers
/// use `/chat/completions`; Qwen uses `/responses` while keeping the same compatible-mode base.
enum LLMWire {
    /// Mirror backend `chatCompletionsUrl`: trim trailing slashes; reuse if it already ends in
    /// /chat/completions; otherwise append.
    static func chatCompletionsURL(base: String) -> URL? {
        var s = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        guard !s.isEmpty else { return nil }
        if s.hasSuffix("/chat/completions") { return URL(string: s) }
        return URL(string: s + "/chat/completions")
    }

    /// Trim trailing slashes; reuse a complete `/responses` URL; convert a complete
    /// `/chat/completions` URL when a stored custom endpoint is switched to Responses.
    static func responsesURL(base: String) -> URL? {
        var s = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        guard !s.isEmpty else { return nil }
        if s.hasSuffix("/responses") { return URL(string: s) }
        if s.hasSuffix("/chat/completions") {
            s = String(s.dropLast("/chat/completions".count))
        }
        return URL(string: s + "/responses")
    }

    /// Mirror backend `modelsUrl` (used by Validate / Fetch models): swap a trailing
    /// /chat/completions for /models, reuse a trailing /models, else append /models.
    static func modelsURL(base: String) -> URL? {
        var s = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        guard !s.isEmpty else { return nil }
        if s.hasSuffix("/models") { return URL(string: s) }
        if s.hasSuffix("/chat/completions") { s = String(s.dropLast("/chat/completions".count)) }
        return URL(string: s + "/models")
    }

    /// Auth headers by provider. Bearer for most OpenAI-compatible providers; MiMo docs ask callers
    /// to choose either Bearer or `api-key`, and the app uses the documented `api-key` examples.
    static func authHeaders(providerId: String, key: String?) -> [String: String] {
        LLMProviderCapabilities
            .resolve(providerId: providerId, baseURLHost: "")
            .authHeaderStyle
            .headers(key: key)
    }
}
