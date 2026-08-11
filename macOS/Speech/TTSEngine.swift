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
        defaults.string(forKey: defaultsKey)
            .flatMap(TTSEngine.init(rawValue:))
            ?? .sherpaKokoroLocal
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

    /// The selected voice id from the provider-scoped TTS configuration shared by Settings and
    /// the reader. Invalid ids on a closed roster resolve to the catalog default.
    var selectedVoiceID: String? {
        selectedVoiceID(defaults: .standard)
    }

    func selectedVoiceID(defaults: UserDefaults) -> String? {
        guard let pid = providerID else { return nil }
        return ProviderConfigDispatcher(defaults: defaults, keyReader: { _ in nil })
            .resolve(.tts, providerId: pid)
            .voice
    }

    /// Persist a voice pick through the same provider-scoped store used by the TTS Settings card.
    func setSelectedVoiceID(_ voiceID: String, defaults: UserDefaults = .standard) {
        guard let pid = providerID else { return }
        CapabilityProviderConfigStore.set(
            voiceID,
            suffix: "voice",
            providerId: pid,
            capability: .tts,
            defaults: defaults)
        ModelConfigurationEvents.post()
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

    private func makeDirectCloudEngine(
        defaults: UserDefaults,
        session: URLSession,
        keyReader: @escaping (String) -> String?
    ) throws -> DirectCloudTTSEngine {
        guard let providerID else {
            throw TTSError.synthesisFailed("\(title) 暂不支持")
        }
        let effective = ProviderConfigDispatcher(defaults: defaults, keyReader: keyReader)
            .resolve(.tts, providerId: providerID)
        guard let key = effective.apiKey else {
            throw TTSError.missingAPIKey(provider: title)
        }
        guard let voice = effective.voice else {
            throw TTSError.synthesisFailed("\(title) 缺少音色配置")
        }
        let adapter: any CloudTTSAdapter
        switch self {
        case .cloudOpenAI:
            var openAI = OpenAITTSAdapter()
            if let baseURL = URL(string: effective.baseURL) { openAI.baseURL = baseURL }
            adapter = openAI
        case .cloudQwen:
            throw TTSError.synthesisFailed("阿里云百炼应使用实时语音合成引擎")
        case .cloudVolcengine:
            var volcengine = VolcengineTTSAdapter()
            if let baseURL = URL(string: effective.baseURL) { volcengine.baseURL = baseURL }
            adapter = volcengine
        case .cloudMimo:
            var mimo = MiMoTTSAdapter()
            if let baseURL = URL(string: effective.baseURL) { mimo.baseURL = baseURL }
            adapter = mimo
        case .cloudMiniMax:
            var minimax = MiniMaxTTSAdapter()
            if let baseURL = URL(string: effective.baseURL) { minimax.baseURL = baseURL }
            adapter = minimax
        case .cloudGemini:
            var gemini = GeminiTTSAdapter()
            if let baseURL = URL(string: effective.baseURL) { gemini.baseURL = baseURL }
            adapter = gemini
        default: throw TTSError.synthesisFailed("\(title) 暂不支持")
        }
        return DirectCloudTTSEngine(
            adapter: adapter,
            model: effective.model,
            voice: voice,
            key: key,
            session: session)
    }

    private func makeQwenEngine(
        defaults: UserDefaults,
        keyReader: @escaping (String) -> String?
    ) throws -> QwenStreamingTTSEngine {
        guard let providerID else {
            throw TTSError.synthesisFailed("\(title) 暂不支持")
        }
        let effective = ProviderConfigDispatcher(defaults: defaults, keyReader: keyReader)
            .resolve(.tts, providerId: providerID)
        guard let key = effective.apiKey else {
            throw TTSError.missingAPIKey(provider: title)
        }
        guard let voice = effective.voice else {
            throw TTSError.synthesisFailed("\(title) 缺少音色配置")
        }
        return QwenStreamingTTSEngine(
            key: key,
            model: effective.model,
            voice: voice,
            region: effective.region == ProviderRegion.singapore
                || effective.region == ProviderRegion.intl
                ? .singapore
                : .china)
    }

}
