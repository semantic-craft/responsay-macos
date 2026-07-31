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
        if capability == .llm {
            // 技能平台模型的 active 镜像随提供商切换重置为「跟随」，否则上一家的模型 ID 会
            // 泄漏给新提供商；per-provider 的 scoped 值保留，切回时自动恢复。
            defaults.set("", forKey: key(SkillPlatformModelSettings.suffix, capability: capability))
        }
        defaults.set(preset.presetVoices.first?.id ?? "", forKey: key("voice", capability: capability))
        let baseURL = preset.endpoint(for: capability, region: region, plan: plan)?.baseURL ?? ""
        defaults.set(baseURL, forKey: key("baseURL", capability: capability))
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
