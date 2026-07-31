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
            // `auto`，不能用 `required`：百炼 Responses 的服务端工具循环里 required 约束每一轮
            // 生成，模型搜完也无法转入文本输出，只能重复搜索，必然被服务端以
            // 「Repetitive tool calls detected」HTTP 400 拒绝（类案检索 0/3，live eval 2026-07-31）。
            // `max_tool_calls: 3` 与 Ark 搜索请求的生产参数同款：给服务端循环和搜索成本封顶。
            // 已知残留：qwen3.7-flash 在多轮检索任务上仍会以相同参数重复调用而触发服务端拦截
            // （cap=3/cap=1 实测均无法根治，qwen3.7-max 3/3 正常收敛）——找类案建议配合
            // 技能平台模型（如 qwen3.7-max）使用。
            return [
                "tool_choice": "auto",
                "max_tool_calls": 3,
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
