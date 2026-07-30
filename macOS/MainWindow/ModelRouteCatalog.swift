import Foundation
import ResponsayCore

/// Encodes a model-route option id as `base` (single-plan / local) or `base#<plan>` for a
/// multi-plan provider, so 按量付费 / Token Plan are distinct selectable entries that share one
/// provider config + per-plan keys.
enum ModelRouteOptionID {
    static func make(_ base: String, plan: BillingPlan?) -> String {
        guard let plan else { return base }
        return "\(base)#\(plan.rawValue)"
    }

    static func parse(_ id: String) -> (base: String, plan: BillingPlan?) {
        let parts = id.split(separator: "#", maxSplits: 1)
        if parts.count == 2, let plan = BillingPlan(rawValue: String(parts[1])) {
            return (String(parts[0]), plan)
        }
        return (id, nil)
    }
}

/// Single source of truth for the ASR / LLM / TTS model-route options and the currently
/// selected id, read fresh from `UserDefaults`. Both the main-panel quick picker
/// (`CurrentModelSelectionCard`) and the menu-bar submenus (`MenuBarContentView`)
/// consume this, so the two surfaces never drift on "what models exist" or
/// "which one is on". Pairs with `ModelRouteSelectionActions`, which performs the
/// writes.
enum ModelRouteCatalog {

    // MARK: - Options

    static var asrOptions: [CurrentModelOption] {
        ASREngine.selectableCases.flatMap { engine -> [CurrentModelOption] in
            guard let providerId = engine.associatedProviderId else {
                return [CurrentModelOption(id: engine.rawValue, title: engine.title, subtitle: "", badge: "本机")]
            }
            return planVariants(providerId: providerId, capability: .asr,
                                base: engine.rawValue, baseTitle: engine.title, badge: "云端")
        }
    }

    static var llmOptions: [CurrentModelOption] {
        ProviderCatalog.presets(for: .llm).flatMap { provider in
            planVariants(providerId: provider.id, capability: .llm,
                         base: provider.id, baseTitle: provider.displayName(for: .llm), badge: "云端")
        }
    }

    static var ttsOptions: [CurrentModelOption] {
        TTSEngine.selectableCases.map {
            CurrentModelOption(id: $0.rawValue, title: $0.title, subtitle: "", badge: $0.providerID == nil ? "本机" : "云端")
        }
    }

    /// One option per billing plan for a multi-plan provider (小米Mimo · 按量付费 / · Token Plan),
    /// otherwise a single option. The menu filter hides plans without a key, so only the plans
    /// the user has actually configured show up.
    private static func planVariants(
        providerId: String,
        capability: ModelCapability,
        base: String,
        baseTitle: String,
        badge: String
    ) -> [CurrentModelOption] {
        guard let preset = ProviderCatalog.presets(for: capability).first(where: { $0.id == providerId }),
              preset.plans(for: capability).count > 1
        else {
            return [CurrentModelOption(id: base, title: baseTitle, subtitle: "", badge: badge)]
        }
        return preset.plans(for: capability).map { plan in
            CurrentModelOption(
                id: ModelRouteOptionID.make(base, plan: plan),
                title: "\(baseTitle) · \(plan.label)",
                subtitle: "",
                badge: badge)
        }
    }

    // MARK: - Current selection

    static func currentASRId(defaults: UserDefaults = .standard) -> String {
        let engine = ASREngine.selected(defaults: defaults)
        guard let providerId = engine.associatedProviderId,
              ProviderCatalog.providerHasMultipleBillingPlans(providerId, capability: .asr)
        else {
            return engine.rawValue
        }
        let plan = ProviderConfigDispatcher(defaults: defaults, keyReader: { _ in nil }).resolve(.asr).plan
        return ModelRouteOptionID.make(engine.rawValue, plan: plan)
    }

    static func currentLLMId(defaults: UserDefaults = .standard) -> String {
        let stored = defaults.string(forKey: "byok.llm.provider") ?? ""
        let providerId = ProviderCatalog.presets(for: .llm).contains(where: { $0.id == stored })
            ? stored
            : (ProviderCatalog.presets(for: .llm).first?.id ?? "custom")
        guard ProviderCatalog.providerHasMultipleBillingPlans(providerId, capability: .llm) else {
            return providerId
        }
        let plan = ProviderConfigDispatcher(defaults: defaults, keyReader: { _ in nil }).resolve(.llm).plan
        return ModelRouteOptionID.make(providerId, plan: plan)
    }

    static func currentTTSId(defaults: UserDefaults = .standard) -> String {
        TTSEngine.selected(defaults: defaults).rawValue
    }
}
