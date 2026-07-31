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
        model: String,
        baseURLHost: String,
        searchEnabled: Bool
    ) -> [String: Any] {
        guard searchEnabled else { return [:] }
        switch channel(providerId: providerId, model: model, host: baseURLHost) {
        case .deepSeek:
            // DeepSeek Responses 的服务端 web_search：工具本身只认 `{"type":"web_search"}`,
            // `search_context_size` / `user_location` 会被忽略。也不发 `max_tool_calls` ——
            // 官方明说该字段被忽略，发了只是噪音（百炼那边它是真的在封顶，两家别混）。
            return [
                "tool_choice": "auto",
                "tools": [["type": "web_search"]],
            ]
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
    public static func supportsSearch(providerId: String, model: String, baseURLHost: String) -> Bool {
        channel(providerId: providerId, model: model, host: baseURLHost) != .none
    }

    /// Whether this provider/endpoint can return a source URL for legal verification.
    /// Qwen Responses returns URLs in `web_search_call.action.sources`, so every Qwen Responses
    /// endpoint that supports search can also feed source verification.
    public static func supportsSourceResults(providerId: String, model: String, baseURLHost: String) -> Bool {
        switch channel(providerId: providerId, model: model, host: baseURLHost) {
        case .mimo:
            return true
        case .dashScope:
            return true
        case .deepSeek:
            // 实测 2026-07-31：DeepSeek **没有** Qwen 那种 `action.sources`。它的
            // `web_search_call.action` 是两种形状之一：
            //   {"type":"search","queries":[…]}                     —— 只有检索词，没有 URL
            //   {"type":"open_page","url":"…#ws_call_id=…"}         —— 有 URL，但可能 status:failed
            // 所以来源实际是从正文里的 URL 兜出来的（`parseContentFallback`，实测能拿到正确
            // 链接）。没刻意去读 open_page.url：本次三次调用里它全是 failed，且尾巴挂着
            // `#ws_call_id=` 内部记账片段——拿失败的抓取当「已核验来源」比拿不到更糟。
            // 兜不到就是 nil：「搜不到 ≠ 不存在」，锚点留 pending，不会误判成 rejected。
            return true
        case .none:
            return false
        }
    }

    // MARK: - Channel resolution

    enum Channel { case dashScope, mimo, deepSeek, none }

    /// DeepSeek 的 web_search 是 Responses 专属的服务端工具，所以这里必须跟着
    /// `prefersResponses` 一起按模型收窄：只有走 Responses 的 `deepseek-v4-flash` 能搜。
    /// 别的模型仍在 `/chat/completions` 上，把 `tools:[{type:web_search}]` 发过去会被当成
    /// 缺 function 定义的工具而 400。
    static func channel(providerId: String, model: String, host: String) -> Channel {
        switch providerId.lowercased() {
        case "qwen", "qwen-team":  return .dashScope
        case "mimo", "mimo-payg":  return .mimo
        default: break
        }
        let h = host.lowercased()
        if h.contains("dashscope") || h.contains("aliyuncs") { return .dashScope }
        if h.contains("xiaomimimo")                         { return .mimo }
        if LLMProviderCapabilities.prefersResponses(
            providerId: providerId, model: model, baseURLHost: host),
           providerId.lowercased() == "deepseek" || h.contains("deepseek") {
            return .deepSeek
        }
        return .none
    }
}
