import Foundation

// MARK: - LLMSearchControl
//
// Per-provider web-search enablement for `/chat/completions`. Mirrors
// `LLMThinkingControl`: one global "search requested" flag fans out to each
// provider's own wire format. Providers without search support are no-ops.

public enum LLMSearchControl {

    /// Extra body fields to merge into a `/chat/completions` request when the
    /// caller wants the LLM to perform a web search (e.g. for [待核] verification).
    /// Returns empty dict when `searchEnabled` is false or the provider has no
    /// search capability.
    public static func extraBody(
        providerId: String,
        baseURLHost: String,
        searchEnabled: Bool
    ) -> [String: Any] {
        guard searchEnabled else { return [:] }
        switch channel(providerId: providerId, host: baseURLHost) {
        case .dashScope:
            return ["enable_search": true]
        case .zhipu:
            return [
                "tool_choice": "auto",
                "tools": [[
                    "type": "web_search",
                    "web_search": [
                        "enable": true,
                        "search_engine": "search_pro",
                        "search_result": true,
                    ],
                ]],
            ]
        case .mimo:
            return [
                "thinking": ["type": "disabled"],
                "tool_choice": "auto",
                "tools": [[
                    "type": "web_search",
                    "max_keyword": 3,
                    "force_search": true,
                    "limit": 1,
                ]],
            ]
        case .none:
            return [:]
        }
    }

    /// Whether this provider/endpoint supports web search.
    public static func supportsSearch(providerId: String, baseURLHost: String) -> Bool {
        channel(providerId: providerId, host: baseURLHost) != .none
    }

    /// Whether this provider/endpoint can return a source URL for legal verification.
    /// Qwen's OpenAI-compatible channel can search, but only DashScope native returns
    /// `search_info.search_results`, so source-verification gates are stricter than
    /// plain web-search support.
    public static func supportsSourceResults(providerId: String, baseURLHost: String) -> Bool {
        switch channel(providerId: providerId, host: baseURLHost) {
        case .zhipu, .mimo:
            return true
        case .dashScope:
            return DashScopeSearchRequestBuilder.supportsNativeSourceSearch(
                providerId: providerId,
                baseURLHost: baseURLHost)
        case .none:
            return false
        }
    }

    // MARK: - Channel resolution

    enum Channel { case dashScope, zhipu, mimo, none }

    static func channel(providerId: String, host: String) -> Channel {
        switch providerId.lowercased() {
        case "qwen", "qwen-token-plan", "qwen-team":  return .dashScope
        case "zhipu":              return .zhipu
        case "mimo", "mimo-payg":  return .mimo
        default: break
        }
        let h = host.lowercased()
        if h.contains("dashscope") || h.contains("aliyuncs") { return .dashScope }
        if h.contains("bigmodel")                           { return .zhipu }
        if h.contains("xiaomimimo")                         { return .mimo }
        return .none
    }
}
