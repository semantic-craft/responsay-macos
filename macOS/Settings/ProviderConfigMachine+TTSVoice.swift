import ResponsayCore

extension ProviderConfigMachine {
    /// Re-read the shared TTS voice without rebuilding the rest of an open provider card.
    /// `CapabilityCardView` calls this for the same configuration-change event emitted by the
    /// reader, so an already-visible Settings window does not keep a stale picker value.
    func refreshVoiceFromDefaults() {
        guard capability == .tts else { return }
        resolveTTSVoice()
    }

    func resolveTTSVoice() {
        guard capability == .tts else { return }
        voice = ProviderConfigDispatcher(defaults: defaults, keyReader: { _ in nil })
            .resolve(.tts, providerId: providerId)
            .voice ?? ""
    }

    /// Resolve the Settings card through the same provider state the next synthesis consumes.
    /// Provider-scoped values win over active mirrors, while provider rules normalize retired or
    /// incompatible endpoint/model choices without rewriting the durable scoped profile on load.
    func applyEffectiveTTSConfiguration() {
        let effective = ProviderConfigDispatcher(defaults: defaults, keyReader: keyReader)
            .resolve(.tts, providerId: providerId)
        regionRaw = effective.region.rawValue
        planRaw = effective.plan.rawValue
        baseURL = effective.baseURL
        model = effective.model
        voice = effective.voice ?? ""
        apiKey = effective.apiKey ?? ""
    }
}
