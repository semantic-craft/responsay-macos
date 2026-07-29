import Foundation
import ResponsayCore

/// Keeps the route (`ttsEngine`), active provider (`byok.tts.provider`) and that provider's active
/// runtime config in step. Provider-scoped values remain the durable source of truth, so switching
/// away and back restores the user's model / voice / endpoint instead of catalog defaults.
///
/// This is intentionally UserDefaults-only: launch reconciliation must run before status/menu UI
/// reads `TTSEngine.selected`, without adding a Keychain read to the launch or render path (217).
enum TTSActiveProvider {

    private static let configSuffixes = ["region", "plan", "model", "voice", "baseURL"]
    private static let legacyIdentitySuffixes = ["model", "baseURL"]

    /// The user moved the card's 服务商 dropdown. An explicit pick is intent, so it becomes the
    /// active route even when nothing is configured for it yet.
    static func adopt(_ providerId: String, defaults: UserDefaults = .standard) {
        activate(providerId, defaults: defaults)
    }

    /// Backfill for installs configured before this key was written: adopt the provider the card
    /// is *showing*, but only once it is actually configured and no different explicit route exists.
    /// Merely opening the card must never replace an explicit local/cloud choice.
    static func adoptShownProviderIfUnset(
        _ shownProviderId: String,
        hasCredential: Bool,
        defaults: UserDefaults = .standard
    ) {
        guard (defaults.string(forKey: activeKey) ?? "").isEmpty,
              hasCredential || hasStoredConfig(shownProviderId, defaults: defaults)
        else { return }
        if let explicit = storedEngine(defaults: defaults), explicit.providerID != shownProviderId {
            return
        }
        activate(shownProviderId, defaults: defaults)
    }

    /// Repairs partial state before any menu/overview/read-aloud object resolves the current route.
    /// Priority matches the historical runtime contract: an explicit valid engine wins; otherwise
    /// use the active provider; otherwise recover only a uniquely matching legacy shared/scoped
    /// profile. Ambiguous archived profiles remain untouched instead of guessing by catalog order.
    static func reconcileAtLaunch(defaults: UserDefaults = .standard) {
        if defaults.string(forKey: TTSEngine.defaultsKey) == "cloud-doubao" {
            activate(TTSEngine.cloudQwen.providerID ?? "qwen", defaults: defaults)
            return
        }
        if let explicit = storedEngine(defaults: defaults) {
            guard let providerId = explicit.providerID else { return }
            activate(providerId, defaults: defaults)
            return
        }
        if let providerId = nonEmpty(defaults.string(forKey: activeKey)),
           engine(for: providerId) != nil {
            activate(providerId, defaults: defaults)
            return
        }
        if let providerId = uniqueLegacyProvider(defaults: defaults) {
            activate(providerId, defaults: defaults)
        }
    }

    /// True when the card has persisted config for this provider. `model` is written by every
    /// card path that edits a field (`persist()`), so its presence marks "the user has been here"
    /// without touching the Keychain.
    static func hasStoredConfig(_ providerId: String, defaults: UserDefaults) -> Bool {
        let key = CapabilityProviderConfigStore.scopedKey("model", providerId: providerId, capability: .tts)
        return !(defaults.string(forKey: key) ?? "").isEmpty
    }

    private static func activate(_ providerId: String, defaults: UserDefaults) {
        guard let engine = engine(for: providerId) else { return }
        migrateLegacyActiveConfigIfNeeded(providerId, defaults: defaults)
        restoreActiveConfig(providerId, defaults: defaults)
        defaults.set(providerId, forKey: activeKey)
        defaults.set(engine.rawValue, forKey: TTSEngine.defaultsKey)
    }

    private static func migrateLegacyActiveConfigIfNeeded(
        _ providerId: String,
        defaults: UserDefaults
    ) {
        guard nonEmpty(defaults.string(forKey: activeKey)) == providerId else { return }

        for suffix in configSuffixes {
            let scopedKey = CapabilityProviderConfigStore.scopedKey(
                suffix, providerId: providerId, capability: .tts)
            let activeConfigKey = CapabilityProviderConfigStore.activeKey(suffix, capability: .tts)
            guard defaults.object(forKey: scopedKey) == nil,
                  let activeValue = defaults.string(forKey: activeConfigKey),
                  nonEmpty(activeValue) != nil
            else { continue }
            defaults.set(activeValue, forKey: scopedKey)
        }
    }

    private static func restoreActiveConfig(_ providerId: String, defaults: UserDefaults) {
        guard let preset = ProviderCatalog.presets(for: .tts).first(where: { $0.id == providerId }) else {
            return
        }
        let scopedRegion = scopedString("region", providerId: providerId, defaults: defaults)
        let region = ProviderRegion(rawValue: scopedRegion ?? "") ?? preset.regions(for: .tts).first ?? .global
        let scopedPlan = scopedString("plan", providerId: providerId, defaults: defaults)
        let plan = BillingPlan(rawValue: scopedPlan ?? "") ?? preset.plans(for: .tts).first ?? .payg
        let fallbacks: [String: String] = [
            "region": region.rawValue,
            "plan": plan.rawValue,
            "model": preset.defaultModel(for: .tts, plan: plan) ?? "",
            "voice": preset.presetVoices.first?.id ?? "",
            "baseURL": preset.endpoint(for: .tts, region: region, plan: plan)?.baseURL ?? "",
        ]

        for suffix in configSuffixes {
            let scopedKey = CapabilityProviderConfigStore.scopedKey(
                suffix, providerId: providerId, capability: .tts)
            let activeKey = CapabilityProviderConfigStore.activeKey(suffix, capability: .tts)
            if let stored = defaults.object(forKey: scopedKey) {
                defaults.set(stored, forKey: activeKey)
            } else if let fallback = fallbacks[suffix] {
                defaults.set(fallback, forKey: activeKey)
            }
        }
    }

    private static func uniqueLegacyProvider(defaults: UserDefaults) -> String? {
        let activeEvidence = legacyIdentitySuffixes.compactMap { suffix -> (String, String)? in
            guard let value = nonEmpty(defaults.string(
                forKey: CapabilityProviderConfigStore.activeKey(suffix, capability: .tts))) else {
                return nil
            }
            return (suffix, value)
        }
        guard !activeEvidence.isEmpty else { return nil }

        let matches = TTSEngine.selectableCases.compactMap(\.providerID).filter { providerId in
            var compared = 0
            for (suffix, activeValue) in activeEvidence {
                guard let scopedValue = scopedString(suffix, providerId: providerId, defaults: defaults) else {
                    continue
                }
                compared += 1
                if scopedValue != activeValue { return false }
            }
            return compared > 0
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private static func storedEngine(defaults: UserDefaults) -> TTSEngine? {
        defaults.string(forKey: TTSEngine.defaultsKey).flatMap(TTSEngine.init(rawValue:))
    }

    private static func engine(for providerId: String) -> TTSEngine? {
        TTSEngine.selectableCases.first { $0.providerID == providerId }
    }

    private static func scopedString(_ suffix: String, providerId: String, defaults: UserDefaults) -> String? {
        nonEmpty(defaults.string(forKey: CapabilityProviderConfigStore.scopedKey(
            suffix, providerId: providerId, capability: .tts)))
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static var activeKey: String {
        CapabilityProviderConfigStore.activeKey("provider", capability: .tts)
    }
}
