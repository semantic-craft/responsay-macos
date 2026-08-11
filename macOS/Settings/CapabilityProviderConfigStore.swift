import Foundation

enum CapabilityProviderConfigStore {
    static func providerKey(_ capability: ModelCapability) -> String {
        "byok.\(capability.rawValue).provider"
    }

    static func scopedKey(_ suffix: String, providerId: String, capability: ModelCapability) -> String {
        "byok.\(capability.rawValue).\(providerId).\(suffix)"
    }

    static func string(
        _ suffix: String,
        providerId: String,
        capability: ModelCapability,
        defaults: UserDefaults
    ) -> String? {
        return defaults.string(forKey: scopedKey(suffix, providerId: providerId, capability: capability))
    }

    static func set(
        _ value: Any,
        suffix: String,
        providerId: String,
        capability: ModelCapability,
        defaults: UserDefaults
    ) {
        defaults.set(value, forKey: scopedKey(suffix, providerId: providerId, capability: capability))
    }
}
