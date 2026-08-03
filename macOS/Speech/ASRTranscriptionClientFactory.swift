import Foundation
import ResponsayCore

/// Builds app-direct ASR clients from the same BYOK settings card slots the UI writes.
///
/// Biasing-route source of truth: `ASREngineBiasingProfile`. When you change which biasing
/// closure a factory method wires (`hotwordsProvider` = weakPrompt), update that profile +
/// `ASREngineBiasingProfileTests`, or the documented
/// per-engine biasing reach drifts silently.
enum ASRTranscriptionClientFactory {
    typealias KeyReader = @Sendable (String) -> String?

    static func openAI(
        defaults: UserDefaults = .standard,
        session: URLSession = .shared,
        profileProvider: @escaping @Sendable () -> SpeechCaptureProfile = { .dictation },
        keyReader: @escaping KeyReader = { BYOKKeychain.read($0) }
    ) -> DirectOpenAITranscriptionAPI {
        let settings = DefaultsReader(defaults: defaults)
        return DirectOpenAITranscriptionAPI(
            baseURL: baseURL(
                forProvider: "openai",
                fallback: URL(string: "https://api.openai.com/v1")!,
                defaults: defaults),
            session: session,
            hotwordsProvider: { ContextHotwordSettings.asrWeakPrompt() },   // 517: 词典 + 当次屏幕临时词
            profileProvider: profileProvider,
            modelProvider: {
                settings.model(forProvider: "openai", fallback: "gpt-4o-transcribe")
            },
            apiKeyProvider: { apiKey(forProvider: "openai", plan: settings.asrPlan(forProvider: "openai"), keyReader: keyReader) })
    }

    static func mimo(
        defaults: UserDefaults = .standard,
        session: URLSession = .shared,
        profileProvider: @escaping @Sendable () -> SpeechCaptureProfile = { .dictation },
        keyReader: @escaping KeyReader = { BYOKKeychain.read($0) }
    ) -> DirectMimoTranscriptionAPI {
        let settings = DefaultsReader(defaults: defaults)
        return DirectMimoTranscriptionAPI(
            baseURL: baseURL(
                forProvider: "mimo",
                fallback: URL(string: MiMoASRRouting.tokenPlanChinaBaseURL)!,
                defaults: defaults),
            session: session,
            hotwordsProvider: { ContextHotwordSettings.asrWeakPrompt() },   // 517: 词典 + 当次屏幕临时词
            profileProvider: profileProvider,
            modelProvider: {
                settings.model(forProvider: "mimo", fallback: "mimo-v2.5-asr")
            },
            apiKeyProvider: { apiKey(forProvider: "mimo", plan: settings.asrPlan(forProvider: "mimo"), keyReader: keyReader) })
    }

    /// Google Gemini batch ASR (整段识别). Unlike the OpenAI-compatible clients
    /// this hits the native `:generateContent` endpoint with `x-goog-api-key`
    /// (see DirectGeminiTranscriptionAPI); the BYOK key is the same Gemini slot
    /// the LLM/TTS lanes use. Base URL resolves to the native host, not the
    /// `/v1beta/openai/` LLM endpoint, via the preset's `.asr` capabilityEndpoints.
    static func gemini(
        defaults: UserDefaults = .standard,
        session: URLSession = .shared,
        profileProvider: @escaping @Sendable () -> SpeechCaptureProfile = { .dictation },
        keyReader: @escaping KeyReader = { BYOKKeychain.read($0) }
    ) -> DirectGeminiTranscriptionAPI {
        let settings = DefaultsReader(defaults: defaults)
        return DirectGeminiTranscriptionAPI(
            baseURL: baseURL(
                forProvider: "gemini",
                fallback: URL(string: "https://generativelanguage.googleapis.com/v1beta/")!,
                defaults: defaults),
            session: session,
            hotwordsProvider: { ContextHotwordSettings.asrWeakPrompt() },   // 517: 词典 + 当次屏幕临时词
            profileProvider: profileProvider,
            modelProvider: {
                settings.model(forProvider: "gemini", fallback: "gemini-3.1-flash-lite")
            },
            apiKeyProvider: { apiKey(forProvider: "gemini", plan: settings.asrPlan(forProvider: "gemini"), keyReader: keyReader) })
    }

    static func customOpenAI(
        defaults: UserDefaults = .standard,
        session: URLSession = .shared,
        profileProvider: @escaping @Sendable () -> SpeechCaptureProfile = { .dictation },
        keyReader: @escaping KeyReader = { BYOKKeychain.read($0) }
    ) -> DirectOpenAITranscriptionAPI {
        let settings = DefaultsReader(defaults: defaults)
        return DirectOpenAITranscriptionAPI(
            baseURL: CustomASREndpoint.baseURL(defaults: defaults),
            session: session,
            hotwordsProvider: { ContextHotwordSettings.asrWeakPrompt() },   // 517: 词典 + 当次屏幕临时词
            profileProvider: profileProvider,
            modelProvider: { settings.customModel() },
            apiKeyProvider: { apiKey(forProvider: CustomASREndpoint.providerID, plan: settings.asrPlan(forProvider: CustomASREndpoint.providerID), keyReader: keyReader) })
    }

    static func volcengineFlash(
        defaults: UserDefaults = .standard,
        session: URLSession = .shared,
        profileProvider: @escaping @Sendable () -> SpeechCaptureProfile = { .dictation },
        keyReader: @escaping KeyReader = { BYOKKeychain.read($0) }
    ) -> DirectVolcengineFlashTranscriptionAPI {
        _ = profileProvider
        let settings = DefaultsReader(defaults: defaults)
        return DirectVolcengineFlashTranscriptionAPI(
            baseURL: baseURL(
                forProvider: "volcengine-flash",
                fallback: URL(string: "https://openspeech.bytedance.com/api/v3")!,
                defaults: defaults),
            session: session,
            modelProvider: {
                settings.model(forProvider: "volcengine-flash", fallback: "bigmodel")
            },
            apiKeyProvider: {
                apiKey(
                    forProvider: "volcengine-flash",
                    plan: settings.asrPlan(forProvider: "volcengine-flash"),
                    keyReader: keyReader)
            })
    }

    /// 火山引擎 大模型流式 (bigmodel_nostream, #580). Reuses the `volcengine-flash` key slot (same 火山
    /// account) and feeds 词典 hotwords through the request's `corpus.context` biasing channel.
    static func volcengineRealtime(
        defaults: UserDefaults = .standard,
        session: URLSession = .shared,
        profileProvider: @escaping @Sendable () -> SpeechCaptureProfile = { .dictation },
        keyReader: @escaping KeyReader = { BYOKKeychain.read($0) }
    ) -> VolcengineRealtimeTranscriptionAPI {
        _ = profileProvider
        let settings = DefaultsReader(defaults: defaults)
        let key = apiKey(
            forProvider: "volcengine-flash",
            plan: settings.asrPlan(forProvider: "volcengine-flash"),
            keyReader: keyReader)
        return VolcengineRealtimeTranscriptionAPI(
            endpoint: VolcengineRealtimeEndpoint(apiKey: key),
            // #580: whole-utterance semantic mode (bigmodel_nostream endpoint) — the #579
            // param combo was self-defeating per the full docs (enable_nonstream forces
            // 800ms VAD splits and voids vad_segment_duration). Plain config; the endpoint
            // choice does the work now.
            config: VolcengineRealtimeConfig(
                hotwords: ContextHotwordSettings.biasingSets().weakPrompt(augmentedWith: [])),
            session: session)
    }

    /// 阿里云百炼 实时语音识别 (#588/#52): each capture gets a fresh run-task on a bounded reusable
    /// WebSocket — frames stream while the hotkey is held, and `finish-task` on release yields the
    /// 整段 transcript. The host is the
    /// business-space dedicated domain when the card carries a Workspace ID, otherwise the generic
    /// DashScope host; `QwenASRFlashRouting` owns that derivation and the migration off the retired
    /// OmniRealtime values. 词典 hotwords ride the run-task `vocabulary` 即时热词 field.
    ///
    /// Resolved fresh per capture (the capture service calls this in `start()`), so a provider /
    /// region / Workspace / model / key change takes effect without an app restart.
    static func qwenRunTaskConfig(
        defaults: UserDefaults = .standard,
        context: [String] = [],
        contextScope: String? = nil,
        keyReader: KeyReader = { BYOKKeychain.read($0) }
    ) -> QwenRunTaskCaptureConfig {
        let providerId = QwenASRFlashRouting.providerId
        let settings = DefaultsReader(defaults: defaults)
        let preset = ProviderCatalog.presets(for: .asr).first { $0.id == providerId }
        let providerMatches = ASRModelSelection.providerMatches(
            defaults.string(forKey: "byok.asr.provider"), providerId)
        let region = providerMatches
            ? ProviderRegion(rawValue: defaults.string(forKey: "byok.asr.region") ?? "")
                ?? preset?.regions(for: .asr).first ?? .china
            : preset?.regions(for: .asr).first ?? .china
        let workspaceID = CapabilityProviderConfigStore.string(
            "workspaceId", providerId: providerId, capability: .asr, defaults: defaults,
            activeProviderId: defaults.string(forKey: "byok.asr.provider"))
        let streamingMode = QwenASRStreamingModeSettings.mode(defaults: defaults)
        return QwenRunTaskCaptureConfig(
            endpoint: QwenASRFlashRouting.endpoint(workspaceID: workspaceID, region: region),
            apiKey: apiKey(
                forProvider: providerId,
                plan: settings.asrPlan(forProvider: providerId),
                keyReader: keyReader),
            model: QwenASRFlashRouting.normalizedModel(
                stored: settings.model(forProvider: providerId, fallback: QwenASRFlashRouting.defaultModel),
                fallback: QwenASRFlashRouting.defaultModel),
            hotwords: ContextHotwordSettings.asrWeakPrompt(defaults: defaults),   // 517: 词典 + 当次屏幕临时词
            context: context,
            contextScope: contextScope,
            heartbeat: true,
            semanticPunctuationEnabled: streamingMode == .longForm,
            multiThresholdModeEnabled: streamingMode == .quick)
    }

    // 按量付费 (sk-) and Token Plan (tp-) keep separate keys for multi-plan providers (e.g.
    // MiMo) — read the slot for the given ASR plan. `plan` is resolved at build time (the
    // client is rebuilt per capture) so the @Sendable apiKeyProvider closure captures only
    // Sendable values (plan + keyReader), never the non-Sendable UserDefaults.
    private static func apiKey(
        forProvider providerId: String,
        plan: BillingPlan,
        keyReader: KeyReader
    ) -> String {
        nonEmpty(keyReader(CapabilityCredentialAccount.apiKeyAccount(
            providerId: providerId, capability: .asr, plan: plan))) ?? ""
    }

    fileprivate static func resolvedPlan(forProvider providerId: String, defaults: UserDefaults) -> BillingPlan {
        let providerMatches = ASRModelSelection.providerMatches(
            defaults.string(forKey: "byok.asr.provider"), providerId)
        let storedPlan = providerMatches
            ? BillingPlan(rawValue: defaults.string(forKey: "byok.asr.plan") ?? "")
            : nil
        let preset = ProviderCatalog.presets(for: .asr).first { $0.id == providerId }
        return MiMoASRRouting.normalizedPlan(
            providerId: providerId, capability: .asr,
            stored: storedPlan, fallback: preset?.plans(for: .asr).first ?? .payg)
    }

    private static func baseURL(
        forProvider providerId: String,
        fallback: URL,
        defaults: UserDefaults
    ) -> URL {
        let providerMatches = ASRModelSelection.providerMatches(
            defaults.string(forKey: "byok.asr.provider"),
            providerId)
        if providerMatches,
           let custom = nonEmpty(defaults.string(forKey: "byok.asr.baseURL")),
           let url = URL(string: MiMoASRRouting.normalizedBaseURL(
            providerId: providerId,
            capability: .asr,
            stored: custom,
            fallback: MiMoASRRouting.tokenPlanChinaBaseURL)) {
            return url
        }
        guard let preset = ProviderCatalog.presets(for: .asr)
            .first(where: { $0.id == providerId }) else {
            return fallback
        }
        let region = providerMatches
            ? ProviderRegion(rawValue: defaults.string(forKey: "byok.asr.region") ?? "") ?? preset.regions(for: .asr).first ?? .global
            : preset.regions(for: .asr).first ?? .global
        let storedPlan = providerMatches
            ? BillingPlan(rawValue: defaults.string(forKey: "byok.asr.plan") ?? "")
            : nil
        let plan = MiMoASRRouting.normalizedPlan(
            providerId: providerId,
            capability: .asr,
            stored: storedPlan,
            fallback: preset.plans(for: .asr).first ?? .payg)
        guard let raw = preset.endpoint(for: .asr, region: region, plan: plan)?.baseURL,
              let url = URL(string: raw) else {
            return fallback
        }
        return url
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

private struct DefaultsReader: @unchecked Sendable {
    let defaults: UserDefaults

    func model(forProvider providerId: String, fallback: String) -> String {
        ASRModelSelection.model(forProvider: providerId, fallback: fallback, defaults: defaults)
    }

    func customModel() -> String {
        CustomASREndpoint.model(defaults: defaults)
    }

    /// Resolve the active ASR billing plan for this provider — used to pick the per-plan key
    /// slot. Lives here so the @Sendable apiKeyProvider closure captures this (@unchecked
    /// Sendable) reader rather than the non-Sendable UserDefaults directly.
    func asrPlan(forProvider providerId: String) -> BillingPlan {
        ASRTranscriptionClientFactory.resolvedPlan(forProvider: providerId, defaults: defaults)
    }
}
