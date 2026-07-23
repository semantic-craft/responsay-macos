import Foundation

/// The opt-in switch for the BYOK-LLM correction tier (#500 S3). **Default OFF** — the tier sends
/// the (already on-device hard-matched) transcript to the user's configured text LLM only when they
/// turn this on AND a usable cloud BYOK model is configured AND a near-miss hotword actually
/// survives. With the switch off — the default — nothing ever leaves the device for this feature.
enum HotwordLLMCorrectionSettings {
    static let key = "hotword.llmCorrection"

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key)   // absent → false (default OFF)
    }

    static func setEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: key)
    }
}
