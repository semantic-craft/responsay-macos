import Foundation

enum CapabilityProviderConfigStore {
    static func activeKey(_ suffix: String, capability: ModelCapability) -> String {
        "byok.\(capability.rawValue).\(suffix)"
    }

    static func scopedKey(_ suffix: String, providerId: String, capability: ModelCapability) -> String {
        "byok.\(capability.rawValue).\(providerId).\(suffix)"
    }

    static func string(
        _ suffix: String,
        providerId: String,
        capability: ModelCapability,
        defaults: UserDefaults,
        activeProviderId: String?
    ) -> String? {
        if let scoped = defaults.string(forKey: scopedKey(suffix, providerId: providerId, capability: capability)) {
            return scoped
        }
        guard CapabilitySelectionSync.providerMatches(activeProviderId, providerId, capability: capability) else {
            return nil
        }
        return defaults.string(forKey: activeKey(suffix, capability: capability))
    }

    static func set(
        _ value: Any,
        suffix: String,
        providerId: String,
        capability: ModelCapability,
        defaults: UserDefaults,
        activeProviderId: String?
    ) {
        defaults.set(value, forKey: scopedKey(suffix, providerId: providerId, capability: capability))
        if CapabilitySelectionSync.providerMatches(activeProviderId, providerId, capability: capability) {
            defaults.set(value, forKey: activeKey(suffix, capability: capability))
        }
    }
}
