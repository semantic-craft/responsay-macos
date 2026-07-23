import Foundation
import ResponsayCore

/// Bridges the BYOK 「模型与密钥」LLM card to the App-direct path (epic 238). `resolveText`
/// (rewrite / translate / express / legal) resolves the BYOK cloud card, or `nil` → backend fallback.
enum LLMEndpointResolver {
    /// UserDefaults key the LLM card's 思考 toggle writes (`byok.llm.thinking`).
    static let thinkingKey = "byok.llm.thinking"

    /// Surfaced when no model is configured at all (no BYOK key). App-direct is the only path now
    /// that the backend LLM routes are retired (245), so this gives actionable setup guidance
    /// instead of a confusing connection failure.
    static var notConfigured: any Error {
        CoachAPIError.message(
            "还没配置可用模型。请在 设置 →「文本改写连接配置」填一个自带 Key。")
    }

    /// Text REWRITE actions (express / polish / rewrite / translate / legal). Thinking is
    /// **always off** (435) — a structured rewrite gains nothing from reasoning and it's slow —
    /// decoupled from the global 思考 toggle. Resolves the BYOK cloud card (nil if unconfigured).
    static func resolveText(
        defaults: UserDefaults = .standard,
        dispatcher: ProviderConfigDispatcher = ProviderConfigDispatcher()
    ) -> LLMEndpoint? {
        resolve(purpose: .rewrite, defaults: defaults, dispatcher: dispatcher)
    }

    /// Open CHAT (voice assistant / 任意提问). Honors the user's global 思考 toggle (435) — the
    /// one surface where reasoning is the user's call. Same provider resolution as `resolveText`.
    static func resolveChat(
        defaults: UserDefaults = .standard,
        dispatcher: ProviderConfigDispatcher = ProviderConfigDispatcher()
    ) -> LLMEndpoint? {
        resolve(purpose: .chat, defaults: defaults, dispatcher: dispatcher)
    }

    /// 任意提问 联网搜索专属端点。Resolves the user's chosen (or 自动) search-capable provider
    /// (Qwen/智谱/MiMo — `LLMSearchControl`) into a configured endpoint, **independent of the main
    /// chat model**, so 联网搜索 works even when the active LLM can't search. `自动` prefers the
    /// active chat provider when it already supports search (no extra config), else the first
    /// search-capable provider with a key. `nil` = none configured → caller falls back to plain chat.
    static func resolveSearch(
        defaults: UserDefaults = .standard,
        dispatcher: ProviderConfigDispatcher = ProviderConfigDispatcher()
    ) -> LLMEndpoint? {
        let thinking = LLMThinkingPolicy.thinkingEnabled(
            purpose: .chat, globalToggle: defaults.bool(forKey: thinkingKey))
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
            guard cfg.hasKey else { continue }
            let endpoint = LLMEndpoint(
                providerId: cfg.providerId,
                baseURL: cfg.baseURL,
                model: cfg.model,
                apiKey: cfg.apiKey,
                thinkingEnabled: thinking)
            if endpoint.isConfigured { return endpoint }
        }
        return nil
    }

    /// Shared resolution for text + chat: the only difference is whether thinking is enabled,
    /// decided by `LLMThinkingPolicy` from the purpose + the global toggle.
    private static func resolve(
        purpose: LLMThinkingPurpose,
        defaults: UserDefaults,
        dispatcher: ProviderConfigDispatcher
    ) -> LLMEndpoint? {
        let thinking = LLMThinkingPolicy.thinkingEnabled(
            purpose: purpose, globalToggle: defaults.bool(forKey: thinkingKey))
        let cfg = dispatcher.resolve(.llm)
        let endpoint = LLMEndpoint(
            providerId: cfg.providerId,
            baseURL: cfg.baseURL,
            model: cfg.model,
            apiKey: cfg.apiKey,
            thinkingEnabled: thinking)
        return endpoint.isConfigured ? endpoint : nil
    }

    /// Whether any LLM is usable for text actions (a configured BYOK cloud card). When false,
    /// text transforms pass through the raw input instead of erroring (#390, spec §6 — 纯听写降级).
    static func isConfigured(
        defaults: UserDefaults = .standard,
        dispatcher: ProviderConfigDispatcher = ProviderConfigDispatcher()
    ) -> Bool {
        resolveText(defaults: defaults, dispatcher: dispatcher) != nil
    }

    /// Cloud-only. The BYOK card, or `nil` when not configured → backend fallback.
    /// ponytail: no production caller since the autolearn 云端智能 tier was cut; kept because it
    /// has its own unit tests and is a reusable cloud-class primitive. Delete with its tests if it
    /// stays unused.
    static func resolveCloud(
        defaults: UserDefaults = .standard,
        dispatcher: ProviderConfigDispatcher = ProviderConfigDispatcher()
    ) -> LLMEndpoint? {
        let cfg = dispatcher.resolve(.llm)
        let endpoint = LLMEndpoint(
            providerId: cfg.providerId,
            baseURL: cfg.baseURL,
            model: cfg.model,
            apiKey: cfg.apiKey,
            thinkingEnabled: defaults.bool(forKey: thinkingKey))
        return endpoint.isConfigured ? endpoint : nil
    }
}
