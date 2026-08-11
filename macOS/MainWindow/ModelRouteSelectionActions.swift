import Foundation
import ResponsayCore

enum ModelRouteSelectionActions {
    static func applyASRSelection(_ id: String, defaults: UserDefaults = .standard) {
        defer { ModelConfigurationEvents.post() }
        let (raw, plan) = ModelRouteOptionID.parse(id)
        defaults.set(raw, forKey: ASREngine.defaultsKey)
        guard let providerId = ASREngine(rawValue: raw)?.associatedProviderId else { return }
        ProviderConfigDispatcher(defaults: defaults, keyReader: { _ in nil })
            .selectProvider(providerId, capability: .asr)
        if let plan { applyASRPlan(plan, providerId: providerId, defaults: defaults) }
    }

    static func applyLLMSelection(_ id: String, defaults: UserDefaults = .standard) {
        defer { ModelConfigurationEvents.post() }
        let (base, plan) = ModelRouteOptionID.parse(id)
        guard let preset = ProviderCatalog.presets(for: .llm).first(where: { $0.id == base }) else {
            return
        }

        let dispatcher = ProviderConfigDispatcher(defaults: defaults, keyReader: { _ in nil })
        let previous = dispatcher.resolveLLM(providerId: base).provider
        let selected = plan.map { dispatcher.resolveLLM(providerId: base, plan: $0).provider }
            ?? previous
        dispatcher.selectProvider(base, capability: .llm)
        persistLLMSelection(
            selected,
            previous: previous,
            preset: preset,
            defaults: defaults)
    }

    static func applyTTSSelection(_ id: String, defaults: UserDefaults = .standard) {
        defer { ModelConfigurationEvents.post() }
        defaults.set(id, forKey: TTSEngine.defaultsKey)
        if let providerId = TTSEngine(rawValue: id)?.providerID {
            ProviderConfigDispatcher(defaults: defaults, keyReader: { _ in nil })
                .selectProvider(providerId, capability: .tts)
        }
    }

    static func applyOCRSelection(_ id: String, defaults: UserDefaults = .standard) {
        defaults.set(id, forKey: OCREngine.defaultsKey)
        ModelConfigurationEvents.post()
    }

    /// Switch the active billing plan from the model picker: rewrite plan + Base URL + model so
    /// the next call hits the right host (the per-plan key is already stored separately, keyed by
    /// plan). Mirrors what the settings card's 接入点 dropdown does, so the two surfaces agree.
    private static func applyASRPlan(
        _ plan: BillingPlan,
        providerId: String,
        defaults: UserDefaults
    ) {
        guard let preset = ProviderCatalog.presets(for: .asr)
            .first(where: { $0.id == providerId }) else { return }
        let storedRegion = CapabilityProviderConfigStore.string(
            "region", providerId: providerId, capability: .asr, defaults: defaults)
        let requestedRegion = ProviderRegion(rawValue: storedRegion ?? "")
            ?? preset.regions(for: .asr).first ?? .global
        let endpoint = preset.effectiveASREndpoint(
            requestedRegion: requestedRegion,
            plan: plan)
        let region = endpoint?.region ?? requestedRegion
        let baseURL = endpoint?.baseURL ?? ""
        let model = preset.defaultModel(for: .asr, plan: plan) ?? ""
        func write(_ suffix: String, _ value: String) {
            CapabilityProviderConfigStore.set(
                value, suffix: suffix, providerId: providerId, capability: .asr,
                defaults: defaults)
        }
        write("region", region.rawValue)
        write("plan", plan.rawValue)
        write("baseURL", baseURL)
        write("model", model)
    }

    /// Persist the already-normalized LLM snapshot selected by the quick picker. Resolution stays
    /// pure in `ProviderConfigDispatcher`; this command handler owns the UserDefaults mutation.
    private static func persistLLMSelection(
        _ selected: ResolvedProviderConfig,
        previous: ResolvedProviderConfig,
        preset: ProviderPreset,
        defaults: UserDefaults
    ) {
        let routeChanged = selected.region != previous.region || selected.plan != previous.plan
        let oldDefault = preset.defaultModel(for: .llm, plan: previous.plan) ?? ""
        let newDefault = preset.defaultModel(for: .llm, plan: selected.plan) ?? ""
        let model = routeChanged && (previous.model.isEmpty || previous.model == oldDefault)
            ? newDefault
            : previous.model

        func write(_ suffix: String, _ value: String) {
            CapabilityProviderConfigStore.set(
                value,
                suffix: suffix,
                providerId: selected.providerId,
                capability: .llm,
                defaults: defaults)
        }
        write("region", selected.region.rawValue)
        write("plan", selected.plan.rawValue)
        write("baseURL", selected.baseURL)
        write("model", model)
        if selected.providerId == "qwen" {
            write("workspaceId", selected.workspaceID ?? "")
        }
    }
}
