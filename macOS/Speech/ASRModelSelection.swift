import Foundation

/// Resolves which ASR model a cloud capture service should request.
///
/// The Settings capability card persists the user's choice under the *global*
/// `byok.asr.model` / `byok.asr.provider` pair (CapabilityCardView). The old
/// per-provider keys (`openai-asr-model`, …) were never written by any UI, so
/// reading them silently pinned every provider to its hard-coded fallback —
/// e.g. OpenAI always ran whisper-1 while the UI claimed gpt-4o-transcribe
/// (audit issue 282).
enum ASRModelSelection {
    /// The user's chosen model when `providerId` is the currently selected ASR
    /// provider; otherwise `fallback` (the catalog default for that provider).
    static func model(
        forProvider providerId: String,
        fallback: String,
        defaults: UserDefaults = .standard
    ) -> String {
        guard providerMatches(defaults.string(forKey: "byok.asr.provider"), providerId),
              let chosen = defaults.string(forKey: "byok.asr.model"),
              !chosen.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return fallback }
        return chosen
    }

    static func providerMatches(_ storedProviderId: String?, _ runtimeProviderId: String) -> Bool {
        canonicalProviderId(storedProviderId) == canonicalProviderId(runtimeProviderId)
    }

    static func canonicalProviderId(_ providerId: String?) -> String? {
        guard let trimmed = providerId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        switch trimmed {
        case "mimo-token-plan":
            return "mimo"
        default:
            return trimmed
        }
    }
}
