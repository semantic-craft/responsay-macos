import Foundation

/// Keychain account namespacing for TTS BYOK keys.
///
/// TTS keys live in a **separate** account namespace (`byok.tts.<provider>`)
/// from the coach / ASR keys (`byok.<provider>`), so a user can route TTS to a
/// different provider/account than their LLM without key collisions
/// (issue 129: "TTS key naming distinct from coach key").
public enum TTSCredential {
    /// Shared Keychain service (same store, distinct account prefix).
    public static let service = "com.responsay.byok"
    public static let accountPrefix = "byok.tts."

    public static func keychainAccount(for providerID: TTSProviderID) -> String {
        accountPrefix + providerID
    }

    /// The coach/ASR account for the same provider — intentionally different.
    public static func coachAccount(for providerID: TTSProviderID) -> String {
        "byok." + providerID
    }
}
