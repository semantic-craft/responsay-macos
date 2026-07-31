import Foundation

/// 思考 fan-out (PRD 2026-06-09, epic 238): maps the requested on/off state to each provider's
/// OWN official thinking parameter, chosen by `provider_id` first and the base-URL host as a
/// fallback (so a 自定义 endpoint pointing at a known vendor still gets the right field). No
/// per-model whitelist — we branch only at the channel level (openless's design).
///
/// The app always asks for **off** (`LLMEndpointResolver` — no user toggle), and emitting the
/// explicit off parameter is exactly what keeps DeepSeek / Gemini / Ollama / MiniMax from
/// reasoning by default. The `enabled` branches stay because the off state is per-vendor, not a
/// blanket omission.
///
/// These are extra top-level body fields merged into the provider's selected text API request.
enum LLMThinkingControl {

    /// Extra request body fields for the chosen 思考 state. Empty = emit nothing
    /// (the safe default for providers with no documented toggle — the model choice decides).
    /// `streaming` remains part of the shared provider contract even though Qwen Responses uses
    /// the same `reasoning.effort` shape for streaming and non-streaming calls.
    static func extraBody(
        providerId: String,
        model: String,
        baseURLHost: String,
        enabled: Bool,
        streaming: Bool
    ) -> [String: Any] {
        switch channel(providerId: providerId, host: baseURLHost) {
        case .openAIReasoning:
            return openAIReasoning(model: model, enabled: enabled)
        case .dashScope:
            return ["reasoning": ["effort": enabled ? "medium" : "none"]]
        case .deepSeek:
            // DeepSeek 的开关随 API 形态换名字，且**思考默认是开的**，所以这里必须发对字段：
            // Responses 用 `reasoning.effort`，`none` 才是关闭；Chat Completions 用
            // `thinking.type`。发错的一方会被静默忽略（官方：不支持的参数不报错），于是模型照常
            // 思考 —— 对输入法来说就是每次改写白等一段思维链。
            // 强度档位（low/high/max）在这里没有意义：关掉之外我们不需要更细的控制。
            if LLMProviderCapabilities.prefersResponses(
                providerId: providerId, model: model, baseURLHost: baseURLHost) {
                return ["reasoning": ["effort": enabled ? "high" : "none"]]
            }
            return ["thinking": ["type": enabled ? "enabled" : "disabled"]]
        case .miniMax:
            // MiniMax OpenAI-compat /v1: M3 injects its interleaved thinking as <think>…</think>
            // INTO `content` by default, corrupting our structured-JSON replies. `reasoning_split`
            // relocates the trace to a separate `reasoning_details` field so `content` stays clean
            // JSON. (`thinking:{type:…}` is the Anthropic-endpoint param — not understood on /v1.)
            // We always split: the app never surfaces the trace, M3 can't fully stop thinking on
            // /v1 (model ceiling), and M2.7-highspeed simply has little to split.
            return ["reasoning_split": true]
        case .openRouter:
            // `exclude:true` runs reasoning but keeps the trace OUT of the response so it never
            // leaks into inserted text (openless polish.rs).
            return ["reasoning": ["effort": enabled ? "medium" : "none", "exclude": true]]
        case .geminiCompat:
            // Gemini's OpenAI-compat layer accepts `reasoning_effort`, but only the older
            // non-pro 2.x/1.x flash-class models accept `"none"` to disable thinking. The 3.5
            // generation — AND the `*-latest` aliases that now resolve to it — HTTP-400 on
            // `reasoning_effort:"none"`, and Pro can't fully disable it anyway (model ceiling).
            // So send `"none"` ONLY for verified non-pro 2.x/1.x ids and OMIT for everything else
            // (3.x, pro, latest aliases, unknown) — omitting never 400s, it just lets the model
            // decide. Detecting the *new* family by substring is what broke: `gemini-flash-latest`
            // contains no "gemini-3", so it wrongly got `"none"` → 400 on every call.
            let acceptsNoneToDisable =
                !model.contains("-pro") && (model.contains("gemini-2") || model.contains("gemini-1"))
            if !enabled && !acceptsNoneToDisable {
                return [:]
            }
            return ["reasoning_effort": enabled ? "medium" : "none"]
        case .mimo:
            return ["thinking": ["type": enabled ? "enabled" : "disabled"]]
        case .doubao:
            return ["thinking": ["type": enabled ? "enabled" : "disabled"]]
        case .ollama:
            // Local reasoning models burn their budget on a hidden trace and return late/empty;
            // reasoning_effort:"none" disables it (the OpenAI-shaped equivalent of the cloud
            // Anthropic thinking:{type:"disabled"} path, per backend text_provider.mjs).
            return enabled ? [:] : ["reasoning_effort": "none"]
        case .none:
            return [:]
        }
    }

    /// OpenAI `reasoning_effort`, only for the actual reasoning families (o1/o3/o4/gpt-5*) — plain
    /// chat models 400 on the field. Strips an `openai/`-style slug prefix (ids users paste) and
    /// forces `gpt-5-pro*` to "high" (it accepts nothing lower). Mirrors openless
    /// `openai_chat_reasoning_effort`.
    static func openAIReasoning(model: String, enabled: Bool) -> [String: Any] {
        var m = model.trimmingCharacters(in: .whitespaces).lowercased()
        if let slash = m.lastIndex(of: "/") { m = String(m[m.index(after: slash)...]) }
        if m.hasPrefix("gpt-5-pro") { return ["reasoning_effort": "high"] }
        guard m.range(of: #"^(o1|o3|o4|gpt-5)"#, options: .regularExpression) != nil else { return [:] }
        return ["reasoning_effort": enabled ? "medium" : "low"]
    }

    enum Channel { case openAIReasoning, dashScope, deepSeek, miniMax, openRouter, geminiCompat, mimo, doubao, ollama, none }

    static func channel(providerId: String, host: String) -> Channel {
        switch providerId.lowercased() {
        case "openai": return .openAIReasoning
        case "qwen", "qwen-team": return .dashScope
        case "deepseek": return .deepSeek
        case "minimax": return .miniMax
        case "gemini": return .geminiCompat
        case "mimo", "mimo-payg": return .mimo
        case "doubao": return .doubao
        case "ollama": return .ollama
        default: break
        }
        // 自定义 endpoint → match the host against known vendors.
        let h = host.lowercased()
        if h.contains("dashscope") || h.contains("aliyuncs") { return .dashScope }
        if h.contains("openrouter") { return .openRouter }
        if h.contains("deepseek") { return .deepSeek }
        if h.contains("minimax") { return .miniMax }
        if h.contains("generativelanguage") { return .geminiCompat }
        if h.contains("xiaomimimo") { return .mimo }
        if h.contains("volces") || h.contains("volcengine") { return .doubao }
        if h == "localhost" || h == "127.0.0.1" { return .ollama }
        if h == "api.openai.com" { return .openAIReasoning }
        return .none
    }
}
