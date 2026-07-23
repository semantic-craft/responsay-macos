import Foundation
import ResponsayCore

enum CapabilitySelectionSync {
    static func selectProvider(
        _ providerId: String,
        capability: ModelCapability,
        defaults: UserDefaults = .standard
    ) {
        let providerKey = key("provider", capability: capability)
        let oldProvider = defaults.string(forKey: providerKey)
        let sameProvider = providerMatches(oldProvider, providerId, capability: capability)
        defaults.set(providerId, forKey: providerKey)
        guard let preset = ProviderCatalog.presets(for: capability).first(where: { $0.id == providerId }) else {
            return
        }
        if sameProvider {
            migrateSameProviderDefaults(providerId, capability: capability, defaults: defaults, preset: preset)
            return
        }

        let region = preset.regions(for: capability).first ?? .global
        let plan = preset.plans(for: capability).first ?? .payg
        defaults.set(region.rawValue, forKey: key("region", capability: capability))
        defaults.set(plan.rawValue, forKey: key("plan", capability: capability))
        defaults.set(preset.defaultModels[capability] ?? "", forKey: key("model", capability: capability))
        defaults.set(preset.presetVoices.first?.id ?? "", forKey: key("voice", capability: capability))
        let baseURL = preset.endpoint(for: capability, region: region, plan: plan)?.baseURL ?? ""
        defaults.set(baseURL, forKey: key("baseURL", capability: capability))
        seedLLMThinkingDefault(providerId, capability: capability, defaults: defaults)
    }

    static func providerMatches(
        _ storedProviderId: String?,
        _ providerId: String,
        capability: ModelCapability
    ) -> Bool {
        if capability == .asr {
            return ASRModelSelection.providerMatches(storedProviderId, providerId)
        }
        return storedProviderId == providerId
    }

    private static func key(_ suffix: String, capability: ModelCapability) -> String {
        "byok.\(capability.rawValue).\(suffix)"
    }

    private static func seedLLMThinkingDefault(
        _ providerId: String,
        capability: ModelCapability,
        defaults: UserDefaults
    ) {
        guard capability == .llm else { return }
        let scopedKey = CapabilityProviderConfigStore.scopedKey(
            "thinking", providerId: providerId, capability: capability)
        if defaults.object(forKey: scopedKey) == nil {
            defaults.set(false, forKey: scopedKey)
        }
        defaults.set(defaults.bool(forKey: scopedKey), forKey: key("thinking", capability: capability))
    }

    private static func migrateSameProviderDefaults(
        _ providerId: String,
        capability: ModelCapability,
        defaults: UserDefaults,
        preset: ProviderPreset
    ) {
        _ = providerId
        _ = capability
        _ = defaults
        _ = preset
    }
}
