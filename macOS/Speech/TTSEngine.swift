import Foundation
import ResponsayCore
import ResponsaySpeech

/// Which engine speaks for 朗读 / 复读 (issue 193). Mirrors `ASREngine`: on-device
/// Kokoro is the default; wired cloud providers go direct-to-provider with BYOK.
enum TTSEngine: String, CaseIterable {
    /// In-process offline TTS via sherpa-onnx + Kokoro (no backend, no Python).
    case sherpaKokoroLocal = "local-kokoro"
    /// Cloud Qwen-Audio 3.0 TTS Flash via direct BYOK.
    case cloudQwen = "cloud-qwen-tts"
    /// Cloud Volcengine TTS (`seed-tts-2.0`) via direct BYOK.
    case cloudVolcengine = "cloud-volcengine-tts"
    /// Cloud OpenAI TTS (`gpt-4o-mini-tts`) via direct BYOK.
    case cloudOpenAI = "cloud-openai-tts"
    /// Cloud MiniMax TTS (`speech-2.8-*`) via direct BYOK.
    case cloudMiniMax = "cloud-minimax"
    /// Cloud MiMo (Xiaomi) `mimo-v2.5-tts` via direct BYOK.
    case cloudMimo = "cloud-mimo"
    /// Cloud Gemini TTS (`gemini-3.1-flash-tts-preview`) via direct BYOK.
    case cloudGemini = "cloud-gemini-tts"

    static let defaultsKey = "ttsEngine"

    static var selectableCases: [TTSEngine] {
        [
            .cloudQwen,
            .cloudVolcengine,
            .cloudMimo,
            .cloudMiniMax,
            .cloudOpenAI,
            .cloudGemini,
            .sherpaKokoroLocal,
        ]
    }

    static var selected: TTSEngine {
        selected(defaults: .standard)
    }

    static func selected(defaults: UserDefaults) -> TTSEngine {
        if defaults.string(forKey: defaultsKey) == "cloud-doubao" {
            return .cloudQwen
        }
        if let raw = defaults.string(forKey: defaultsKey),
           let engine = TTSEngine(rawValue: raw) {
            return engine
        }
        // No explicit engine pick yet → prefer a configured cloud 朗读 voice (the TTS card's active
        // provider, `byok.tts.provider`) over offline Kokoro, matching the other capabilities' BYOK-
        // first posture. Pure UserDefaults read — no Keychain here, keeping it off the settings-render
        // freeze path (217); a missing key still degrades gracefully at synth time via the read-aloud
        // fallback. Kokoro stays the default only when no cloud TTS provider is configured.
        let provider = defaults.string(forKey: "byok.tts.provider") ?? ""
        if !provider.isEmpty,
           let cloudEngine = selectableCases.first(where: { $0.providerID == provider }) {
            return cloudEngine
        }
        return .sherpaKokoroLocal
    }

    // Canonical naming (product decision 2026-06-12): the current route picker
    // shows the provider people recognize; model IDs stay in the Settings model field.
    // NamingCanonTests pins every naming surface to this rule.
    var title: String {
        switch self {
        case .sherpaKokoroLocal: "本机离线 Kokoro"
        case .cloudQwen: "阿里云百炼"
        case .cloudVolcengine: "火山引擎 · 豆包语音"  // 与设置页 provider 名一致(menu==settings)
        case .cloudOpenAI: "OpenAI"
        case .cloudMiniMax: "MiniMax"
        case .cloudMimo: "小米Mimo"
        case .cloudGemini: "Google Gemini"
        }
    }

    /// True for the on-device engine (drives the "去下载" affordance when uninstalled).
    var isLocal: Bool { self == .sherpaKokoroLocal }

    /// Catalog provider id for a cloud engine (issue 196), or `nil` on-device.
    var providerID: TTSProviderID? {
        switch self {
        case .sherpaKokoroLocal: nil
        case .cloudQwen: "qwen"
        case .cloudVolcengine: "volcengine-tts"
        case .cloudOpenAI: "openai"
        case .cloudMimo: "mimo"
        case .cloudMiniMax: "minimax"
        case .cloudGemini: "gemini"
        }
    }

    /// Voice/model catalog for a cloud engine (issue 196).
    var catalog: TTSProviderCatalog? {
        providerID.flatMap(TTSProviderCatalogPresets.catalog(for:))
    }

    /// UserDefaults key holding the user's chosen voice for this engine.
    var voiceDefaultsKey: String { "ttsVoice.\(rawValue)" }

    /// The selected voice id — the TTS Settings card's voice when it targets this
    /// provider, else the legacy per-engine pick if valid, else the catalog default
    /// (issue 196).
    var selectedVoiceID: String? {
        selectedVoiceID(defaults: .standard)
    }

    func selectedVoiceID(defaults: UserDefaults) -> String? {
        guard let catalog else { return nil }

        // The card's voice field is free-form ("输入或选择音色 ID") and most providers accept ids
        // far beyond our curated list (MiniMax cloned voices, the long official rosters). So when
        // the TTS card targets this provider, honor the typed voice verbatim — validating it
        // against the bundled catalog silently swapped any off-catalog voice for the default,
        // which is exactly the wrong failure (a bad id should error audibly at the provider).
        // Qwen is the exception: a fixed surface with a closed, versioned roster where a retired
        // id (e.g. "Cherry") would 400 every 朗读 — there the catalog check stays.
        if let pid = providerID,
           ttsSettingsProvider(defaults: defaults) == pid,
           let byokVoice = nonEmpty(defaults.string(forKey: "byok.tts.voice")),
           !hasClosedVoiceRoster || catalog.voices.contains(where: { $0.id == byokVoice }) {
            return byokVoice
        }

        // The legacy per-engine pick predates the card and can carry stale ids — for that
        // migration path the catalog check stays (issue 196).
        if let stored = defaults.string(forKey: voiceDefaultsKey),
           catalog.voices.contains(where: { $0.id == stored }) {
            return stored
        }
        return catalog.defaults.voiceID
    }

    /// Build the `SpeechSynthesizer` for this engine. Local returns the real Kokoro
    /// engine (throws `.modelNotInstalled` if the voice model isn't downloaded);
    /// wired cloud cases return direct BYOK engines, and unwired providers return a
    /// typed stub.
    func makeSynthesizer(
        defaults: UserDefaults = .standard,
        session: URLSession = .shared,
        keyReader: @escaping (String) -> String? = { BYOKKeychain.read($0) }
    ) throws -> any SpeechSynthesizer {
        switch self {
        case .sherpaKokoroLocal:
            return try SherpaTTSEngine.loadDefault()
        case .cloudQwen:
            return try makeQwenEngine(defaults: defaults, keyReader: keyReader)
        case .cloudOpenAI, .cloudVolcengine, .cloudMimo, .cloudMiniMax, .cloudGemini:
            return try makeDirectCloudEngine(defaults: defaults, session: session, keyReader: keyReader)
        }
    }

    /// Always-usable read-aloud voice (#391, spec §6): the selected engine if it builds
    /// (cloud with a key, or installed Kokoro), else on-device Kokoro if downloaded, else
    /// Apple's system synthesizer. Never throws — read-aloud stays usable even with zero TTS
    /// configuration. Transient: does not mutate the stored selection.
    func resolvedSynthesizer(
        defaults: UserDefaults = .standard,
        session: URLSession = .shared,
        keyReader: @escaping (String) -> String? = { BYOKKeychain.read($0) }
    ) -> any SpeechSynthesizer {
        let selected = try? makeSynthesizer(defaults: defaults, session: session, keyReader: keyReader)
        let kokoroInstalled = LocalModelSpec.kokoroMultiLangV1_1.isInstalled
        switch TTSFallbackPlan.target(selectedReady: selected != nil, kokoroInstalled: kokoroInstalled) {
        case .selected:
            return selected ?? SystemSpeechSynthesizer()
        case .kokoro:
            return (try? SherpaTTSEngine.loadDefault()) ?? SystemSpeechSynthesizer()
        case .system:
            return SystemSpeechSynthesizer()
        }
    }

    /// Low-TTFB streaming synth for engines that support it (issue 197). Throws if
    /// the selected cloud engine is stream-capable but the key is missing.
    func makeStreamingSynthesizer(
        defaults: UserDefaults = .standard,
        keyReader: @escaping (String) -> String? = { BYOKKeychain.read($0) }
    ) throws -> (any StreamingSpeechSynthesizer)? {
        if self == .cloudQwen {
            return try makeQwenEngine(defaults: defaults, keyReader: keyReader)
        }
        // MiMo speaks via the one-shot DirectCloudTTSEngine (its streaming path stalled with
        // no audio); only Qwen streams. Returning nil routes 朗读 to makeSynthesizer().
        return nil
    }

    /// Keychain slot holding this engine's BYOK key (issue 195).
    var credentialSlot: ProviderCredentialStore.Slot? {
        switch self {
        case .cloudOpenAI: .openai
        case .cloudQwen: .dashscope
        case .cloudVolcengine: .volcengine
        case .cloudMimo: .mimo
        case .cloudMiniMax: .minimax
        case .cloudGemini: .gemini
        case .sherpaKokoroLocal: nil
        }
    }

    /// BYOK key for this cloud engine: prefer the 朗读 TTS settings card
    /// (`byok.tts.<providerID>`). The shared `byok.<providerID>` / legacy slot
    /// fallback is only for installs that have not written any TTS card provider yet.
    private func resolvedCloudKey(
        defaults: UserDefaults,
        keyReader: (String) -> String?
    ) -> String? {
        guard let pid = providerID else { return nil }
        // 按量付费 / Token Plan keep separate keys (sk- vs tp-). For a multi-plan provider the
        // key is stored per plan, so read only that plan's slot — never fall back to the
        // sibling plan's key (that would send the wrong key to the host → 401).
        if ProviderCatalog.providerHasMultipleBillingPlans(pid, capability: .tts) {
            let plan = BillingPlan(rawValue: nonEmpty(defaults.string(forKey: "byok.tts.plan")) ?? "") ?? .payg
            return nonEmpty(keyReader(CapabilityCredentialAccount.apiKeyAccount(
                providerId: pid, capability: .tts, plan: plan)))
        }
        if let key = nonEmpty(keyReader(TTSCredential.keychainAccount(for: pid))) {
            return key
        }
        if ttsSettingsProvider(defaults: defaults) != nil {
            return nil
        }
        if let key = nonEmpty(keyReader(TTSCredential.coachAccount(for: pid))) {
            return key
        }
        if let slot = credentialSlot, let k = ProviderCredentialStore.read(slot), !k.isEmpty {
            return k
        }
        return nil
    }

    private func makeDirectCloudEngine(
        defaults: UserDefaults,
        session: URLSession,
        keyReader: (String) -> String?
    ) throws -> DirectCloudTTSEngine {
        guard let catalog, credentialSlot != nil else {
            throw TTSError.synthesisFailed("\(title) 暂不支持")
        }
        guard let key = resolvedCloudKey(defaults: defaults, keyReader: keyReader) else {
            throw TTSError.missingAPIKey(provider: title)
        }
        let adapter: any CloudTTSAdapter
        switch self {
        case .cloudOpenAI:
            var openAI = OpenAITTSAdapter()
            if let baseURL = resolvedTTSBaseURL(defaults: defaults) { openAI.baseURL = baseURL }
            adapter = openAI
        case .cloudQwen:
            throw TTSError.synthesisFailed("阿里云百炼应使用实时语音合成引擎")
        case .cloudVolcengine:
            var volcengine = VolcengineTTSAdapter()
            if let baseURL = resolvedTTSBaseURL(defaults: defaults) { volcengine.baseURL = baseURL }
            adapter = volcengine
        case .cloudMimo:
            var mimo = MiMoTTSAdapter()
            if let baseURL = resolvedTTSBaseURL(defaults: defaults) { mimo.baseURL = baseURL }
            adapter = mimo
        case .cloudMiniMax:
            var minimax = MiniMaxTTSAdapter()
            if let baseURL = resolvedTTSBaseURL(defaults: defaults) { minimax.baseURL = baseURL }
            adapter = minimax
        case .cloudGemini:
            var gemini = GeminiTTSAdapter()
            if let baseURL = resolvedTTSBaseURL(defaults: defaults) { gemini.baseURL = baseURL }
            adapter = gemini
        default: throw TTSError.synthesisFailed("\(title) 暂不支持")
        }
        return DirectCloudTTSEngine(
            adapter: adapter,
            model: resolvedTTSModel(defaults: defaults) ?? catalog.defaults.modelID,
            voice: selectedVoiceID(defaults: defaults) ?? catalog.defaults.voiceID,
            key: key,
            session: session)
    }

    private func makeQwenEngine(
        defaults: UserDefaults,
        keyReader: (String) -> String?
    ) throws -> QwenStreamingTTSEngine {
        guard let key = resolvedCloudKey(defaults: defaults, keyReader: keyReader) else {
            throw TTSError.missingAPIKey(provider: title)
        }
        return QwenStreamingTTSEngine(
            key: key,
            model: catalog?.defaults.modelID ?? "qwen-audio-3.0-tts-flash",
            voice: selectedVoiceID(defaults: defaults)
                ?? catalog?.defaults.voiceID
                ?? "loongeva_v3.6",
            region: resolvedQwenTTSRegion(defaults: defaults))
    }

    private func resolvedTTSModel(defaults: UserDefaults) -> String? {
        guard let pid = providerID,
              ttsSettingsProvider(defaults: defaults) == pid else {
            return catalog?.defaults.modelID
        }
        return resolvedConfiguredTTSModel(defaults: defaults) ?? catalog?.defaults.modelID
    }

    private func resolvedConfiguredTTSModel(defaults: UserDefaults) -> String? {
        guard let pid = providerID,
              ttsSettingsProvider(defaults: defaults) == pid else {
            return nil
        }
        return nonEmpty(defaults.string(forKey: "byok.tts.model"))
    }

    private func resolvedQwenTTSRegion(defaults: UserDefaults) -> QwenRunTaskRegion {
        if ttsSettingsProvider(defaults: defaults) == "qwen",
           let raw = nonEmpty(defaults.string(forKey: "byok.tts.region")) {
            return raw == ProviderRegion.singapore.rawValue || raw == ProviderRegion.intl.rawValue
                ? .singapore
                : .china
        }
        return QwenRunTaskRegion(rawValue: defaults.string(forKey: RealtimeQwenSettings.regionKey) ?? "") ?? .china
    }

    private func resolvedTTSBaseURL(defaults: UserDefaults) -> URL? {
        guard let pid = providerID,
              ttsSettingsProvider(defaults: defaults) == pid,
              let raw = nonEmpty(defaults.string(forKey: "byok.tts.baseURL")) else {
            return nil
        }
        return URL(string: raw)
    }

    /// Whether this engine's provider only accepts voices from its bundled roster. Qwen 语音合成
    /// is a fixed surface (one model, versioned voice list, dispatcher forces the preset voice);
    /// every other cloud provider takes free-form voice ids, so only Qwen validates.
    private var hasClosedVoiceRoster: Bool { self == .cloudQwen }

    private func ttsSettingsProvider(defaults: UserDefaults) -> String? {
        nonEmpty(defaults.string(forKey: "byok.tts.provider"))
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
