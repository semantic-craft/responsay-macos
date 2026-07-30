import Foundation

// MARK: - LLMSearchControl
//
// Per-provider web-search enablement for the provider's selected text API. Mirrors
// `LLMThinkingControl`: one global "search requested" flag fans out to each
// provider's own wire format. Providers without search support are no-ops.

public enum LLMSearchControl {

    /// Extra body fields to merge into a text-generation request when the
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
            // 用户明确开启联网搜索；百炼 Responses 在只有一个工具时允许 required，
            // 避免默认 auto 自行跳过搜索而让“联网”开关名不副实。
            return [
                "tool_choice": "required",
                "tools": [["type": "web_search"]],
            ]
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
    /// Qwen Responses returns URLs in `web_search_call.action.sources`, so every Qwen Responses
    /// endpoint that supports search can also feed source verification.
    public static func supportsSourceResults(providerId: String, baseURLHost: String) -> Bool {
        switch channel(providerId: providerId, host: baseURLHost) {
        case .zhipu, .mimo:
            return true
        case .dashScope:
            return true
        case .none:
            return false
        }
    }

    // MARK: - Channel resolution

    enum Channel { case dashScope, zhipu, mimo, none }

    static func channel(providerId: String, host: String) -> Channel {
        switch providerId.lowercased() {
        case "qwen", "qwen-team":  return .dashScope
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
