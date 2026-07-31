import Foundation

/// Pure URL and auth helpers for OpenAI-compatible text-generation routes. Most BYOK providers
/// use `/chat/completions`; Qwen uses `/responses` while keeping the same compatible-mode base,
/// and DeepSeek `deepseek-v4-flash` uses `/responses` off the un-prefixed base.
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
        // DeepSeek 的 base URL 我们存的是 `https://api.deepseek.com/v1`，但 `/v1` 只是它
        // Chat Completions 的 OpenAI 兼容前缀；Responses 文档给的 base_url 是不带 `/v1` 的
        // `https://api.deepseek.com`。去掉再拼，命中官方文档过的那条路由。
        // （Qwen 的 `/compatible-mode/v1` 不受影响 —— 只按 host 判断。）
        if s.hasSuffix("/v1"), URL(string: s)?.host?.lowercased().contains("deepseek") == true {
            s = String(s.dropLast("/v1".count))
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
