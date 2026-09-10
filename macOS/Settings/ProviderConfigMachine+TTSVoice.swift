import ResponsayCore

extension ProviderConfigMachine {
    var availableTTSVoices: [PresetVoice] {
        guard let catalog = TTSProviderCatalogPresets.catalog(for: providerId) else {
            return current.presetVoices
        }
        return catalog.voices(forModel: model).map { PresetVoice(id: $0.id, displayName: $0.displayName) }
    }

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

}
