import Foundation

/// Promote a configured cloud voice once, at launch or when TTS configuration is saved.
/// Reads of the current route stay cheap and never query the Keychain from a menu body.
enum TTSDefaultSelection {
    static let explicitLocalKey = "ttsLocalExplicitlySelected"

    static func activateConfiguredDefault(
        defaults: UserDefaults = .standard,
        keyReader: @escaping (String) -> String? = { BYOKKeychain.read($0) },
        preferredProviderID: String? = nil
    ) {
        // Old Kokoro values also came from onboarding, so they are defaults. A new manual
        // Kokoro pick has its own marker. Any saved cloud route, automatic or manual, stays put.
        guard TTSEngine.selected(defaults: defaults).isLocal,
              !defaults.bool(forKey: explicitLocalKey) else { return }

        let preferred = preferredProviderID
            ?? defaults.string(forKey: CapabilityProviderConfigStore.providerKey(.tts))
        let clouds = TTSEngine.selectableCases.filter { !$0.isLocal }
        let candidates = clouds.filter { $0.providerID == preferred }
            + clouds.filter { $0.providerID != preferred }
        let readiness = ModelLaneReadinessResolver(dispatcher: ProviderConfigDispatcher(
            defaults: defaults, keyReader: keyReader))
        guard let selected = candidates.first(where: {
            readiness.ttsState(optionId: $0.rawValue).readiness == .cloudReady
        }) else { return }

        defaults.set(selected.rawValue, forKey: TTSEngine.defaultsKey)
        ModelConfigurationEvents.post()
    }
}
