import Foundation
import ResponsayCore

enum ModelRouteSelectionActions {
    static func applyASRSelection(_ id: String, defaults: UserDefaults = .standard) {
        let (raw, plan) = ModelRouteOptionID.parse(id)
        defaults.set(raw, forKey: ASREngine.defaultsKey)
        guard let providerId = ASREngine(rawValue: raw)?.associatedProviderId else { return }
        CapabilitySelectionSync.selectProvider(providerId, capability: .asr, defaults: defaults)
        if let plan { applyPlan(plan, providerId: providerId, capability: .asr, defaults: defaults) }
    }

    static func applyLLMSelection(_ id: String, defaults: UserDefaults = .standard) {
        let (base, plan) = ModelRouteOptionID.parse(id)
        CapabilitySelectionSync.selectProvider(base, capability: .llm, defaults: defaults)
        if let plan { applyPlan(plan, providerId: base, capability: .llm, defaults: defaults) }
    }

    static func applyTTSSelection(_ id: String, defaults: UserDefaults = .standard) {
        defaults.set(id, forKey: TTSEngine.defaultsKey)
        if let providerId = TTSEngine(rawValue: id)?.providerID {
            CapabilitySelectionSync.selectProvider(providerId, capability: .tts, defaults: defaults)
        }
    }

    static func applyOCRSelection(_ id: String, defaults: UserDefaults = .standard) {
        defaults.set(id, forKey: OCREngine.defaultsKey)
    }

    /// Switch the active billing plan from the model picker: rewrite plan + Base URL + model so
    /// the next call hits the right host (the per-plan key is already stored separately, keyed by
    /// plan). Mirrors what the settings card's 接入点 dropdown does, so the two surfaces agree.
    private static func applyPlan(
        _ plan: BillingPlan,
        providerId: String,
        capability: ModelCapability,
        defaults: UserDefaults
    ) {
        guard let preset = ProviderCatalog.presets(for: capability).first(where: { $0.id == providerId }) else { return }
        let storedRegion = CapabilityProviderConfigStore.string(
            "region", providerId: providerId, capability: capability, defaults: defaults, activeProviderId: providerId)
        let region = ProviderRegion(rawValue: storedRegion ?? "") ?? preset.regions(for: capability).first ?? .global
        let baseURL = preset.endpoint(for: capability, region: region, plan: plan)?.baseURL ?? ""
        let model = preset.defaultModel(for: capability, plan: plan) ?? ""
        func write(_ suffix: String, _ value: String) {
            CapabilityProviderConfigStore.set(
                value, suffix: suffix, providerId: providerId, capability: capability,
                defaults: defaults, activeProviderId: providerId)
        }
        write("plan", plan.rawValue)
        write("baseURL", baseURL)
        write("model", model)
    }
}
