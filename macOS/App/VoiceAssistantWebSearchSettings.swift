import Foundation
import ResponsayCore

enum VoiceAssistantWebSearchSettings {
    static let key = "voiceAssistant.webSearchEnabled"

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key)
    }

    static func isSupported(endpoint: LLMEndpoint?) -> Bool {
        guard let endpoint, !endpoint.isLocal else { return false }
        return LLMSearchControl.supportsSearch(
            providerId: endpoint.providerId,
            baseURLHost: endpoint.host)
    }

    static func effectiveEnabled(
        endpoint: LLMEndpoint?,
        defaults: UserDefaults = .standard
    ) -> Bool {
        isEnabled(defaults: defaults) && isSupported(endpoint: endpoint)
    }
}
