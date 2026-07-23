import Foundation

/// Keeps `byok.tts.provider` — the key `TTSEngine.selected` reads to answer "does the user have
/// a cloud 朗读 voice configured?" — in step with the 文本朗读 settings card.
///
/// The card persists per-provider config (`byok.tts.<id>.*`) and the Keychain key, but nothing
/// wrote the *active* provider: only `ModelRouteSelectionActions.applyTTSSelection` did, and that
/// writes `ttsEngine` in the same breath, so `TTSEngine.selected` returned on the explicit-pick
/// line before ever consulting the provider. The cloud-preference branch was therefore
/// unreachable, and a user who had configured 阿里云百炼 in Settings still got offline Kokoro as
/// the default 朗读 engine.
///
/// Only the provider key is written here. The card's `byok.tts.<id>.*` values stay the source of
/// truth for model / voice / endpoint (`CapabilityProviderConfigStore` prefers the scoped key),
/// so adopting a provider never resets what the user picked — unlike
/// `CapabilitySelectionSync.selectProvider`, which rewrites those fields to preset defaults.
/// Pure UserDefaults: no Keychain read, keeping this off the settings-render freeze path (217).
enum TTSActiveProvider {

    /// The user moved the card's 服务商 dropdown. An explicit pick is intent, so it becomes the
    /// active provider even when nothing is configured for it yet.
    static func adopt(_ providerId: String, defaults: UserDefaults = .standard) {
        defaults.set(providerId, forKey: activeKey)
    }

    /// Backfill for installs configured before this key was written: adopt the provider the card
    /// is *showing*, but only once it is actually configured. An install with no cloud TTS at all
    /// must leave the key empty — that emptiness is what keeps Kokoro the default in
    /// `TTSEngine.selected`.
    static func adoptShownProviderIfUnset(
        _ shownProviderId: String,
        hasCredential: Bool,
        defaults: UserDefaults = .standard
    ) {
        guard (defaults.string(forKey: activeKey) ?? "").isEmpty,
              hasCredential || hasStoredConfig(shownProviderId, defaults: defaults)
        else { return }
        adopt(shownProviderId, defaults: defaults)
    }

    /// True when the card has persisted config for this provider. `model` is written by every
    /// card path that edits a field (`persist()`), so its presence marks "the user has been here"
    /// without touching the Keychain.
    static func hasStoredConfig(_ providerId: String, defaults: UserDefaults) -> Bool {
        let key = CapabilityProviderConfigStore.scopedKey("model", providerId: providerId, capability: .tts)
        return !(defaults.string(forKey: key) ?? "").isEmpty
    }

    private static var activeKey: String {
        CapabilityProviderConfigStore.activeKey("provider", capability: .tts)
    }
}
