import Foundation
import ResponsayCore

/// Bridges the BYOK 「模型与密钥」LLM card to the App-direct path (epic 238). `resolveText`
/// (rewrite / translate / express / legal) resolves the BYOK cloud card, or `nil` → backend fallback.
///
/// 思考 is **forced off** on every path — rewrite, chat and 联网搜索 alike. There is no user
/// toggle: the app never surfaces a reasoning trace, and thinking only makes every action slower.
/// `LLMThinkingControl` still emits each provider's official "off" parameter, which is what
/// actually keeps DeepSeek / Gemini / Ollama / MiniMax from reasoning by default.
enum LLMEndpointResolver {
    /// Surfaced when no model is configured at all (no BYOK key). App-direct is the only path now
    /// that the backend LLM routes are retired (245), so this gives actionable setup guidance
    /// instead of a confusing connection failure.
    static var notConfigured: any Error {
        CoachAPIError.message(
            "还没配置可用模型。请在 设置 →「文本改写连接配置」填一个自带 Key。")
    }

    /// Text REWRITE actions (express / polish / rewrite / translate / legal). Resolves the BYOK
    /// cloud card (nil if unconfigured).
    static func resolveText(
        defaults: UserDefaults = .standard,
        dispatcher: ProviderConfigDispatcher? = nil
    ) -> LLMEndpoint? {
        resolve(defaults: defaults, dispatcher: dispatcher, lane: \.dictationEndpoint)
    }

    /// Open CHAT (voice assistant / 任意提问). Same provider resolution as `resolveText`.
    static func resolveChat(
        defaults: UserDefaults = .standard,
        dispatcher: ProviderConfigDispatcher? = nil
    ) -> LLMEndpoint? {
        resolve(defaults: defaults, dispatcher: dispatcher, lane: \.dictationEndpoint)
    }

    /// 技能平台 lane（`LegalSkillRuntime` 技能执行、技能 JSON 修复、无独立检索服务时的技能搜索）。
    /// 与听写 lane 共享同一提供商解析结果 —— provider / Base URL（含 Workspace 派生）/ 凭据完全一致，
    /// 只有 model 可能不同：用户显式选了技能平台模型就覆盖；空 = 跟随听写模型。
    static func resolveSkill(
        defaults: UserDefaults = .standard,
        dispatcher: ProviderConfigDispatcher? = nil
    ) -> LLMEndpoint? {
        resolve(defaults: defaults, dispatcher: dispatcher, lane: \.skillEndpoint)
    }

    /// 任意提问 联网搜索专属端点。Resolves the user's chosen (or 自动) search-capable provider
    /// (Qwen/智谱/MiMo — `LLMSearchControl`) into a configured endpoint, **independent of the main
    /// chat model**, so 联网搜索 works even when the active LLM can't search. `自动` prefers the
    /// active chat provider when it already supports search (no extra config), else the first
    /// search-capable provider with a key. `nil` = none configured → caller falls back to plain chat.
    static func resolveSearch(
        defaults: UserDefaults = .standard,
        dispatcher: ProviderConfigDispatcher? = nil
    ) -> LLMEndpoint? {
        let dispatcher = dispatcher ?? ProviderConfigDispatcher(defaults: defaults)
        var candidates = VoiceAssistantSearchModelSettings.orderedCandidates(defaults: defaults)
        // 自动:若当前主模型本就可联网,优先用它,省得另配密钥(且保持旧行为)。
        if VoiceAssistantSearchModelSettings.preferredProviderId(defaults: defaults) == nil {
            let active = dispatcher.resolve(.llm).providerId
            if VoiceAssistantSearchModelSettings.searchProviders.contains(active) {
                candidates = [active] + candidates.filter { $0 != active }
            }
        }
        for providerId in candidates {
            let cfg = dispatcher.resolve(.llm, providerId: providerId)
            guard ModelLaneReadinessResolver.cloudState(for: cfg).readiness.isReady else { continue }
            let endpoint = LLMEndpoint(
                providerId: cfg.providerId,
                baseURL: cfg.baseURL,
                model: cfg.model,
                apiKey: cfg.apiKey,
                thinkingEnabled: false)
            if endpoint.isConfigured { return endpoint }
        }
        return nil
    }

    /// Shared resolution for text, chat, and skill. Both lanes are projected from the same
    /// effective provider snapshot; only the selected endpoint's model may differ.
    private static func resolve(
        defaults: UserDefaults,
        dispatcher: ProviderConfigDispatcher?,
        lane: KeyPath<ResolvedLLMLanes, LLMEndpoint>
    ) -> LLMEndpoint? {
        let lanes = (dispatcher ?? ProviderConfigDispatcher(defaults: defaults)).resolveLLM()
        guard ModelLaneReadinessResolver.cloudState(for: lanes.provider).readiness.isReady else { return nil }
        let endpoint = lanes[keyPath: lane]
        return endpoint.isConfigured ? endpoint : nil
    }

    /// Whether any LLM is usable for text actions (a configured BYOK cloud card). When false,
    /// text transforms pass through the raw input instead of erroring (#390, spec §6 — 纯听写降级).
    static func isConfigured(
        defaults: UserDefaults = .standard,
        dispatcher: ProviderConfigDispatcher? = nil
    ) -> Bool {
        resolveText(defaults: defaults, dispatcher: dispatcher) != nil
    }

}
