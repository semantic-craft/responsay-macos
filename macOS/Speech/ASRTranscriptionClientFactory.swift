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

    /// Shared production route → client seam for every whole-clip cloud ASR provider. The routed
    /// capture service and the persisted-selection matrix both pass through this switch, so adding
    /// a provider cannot leave settings routing and runtime construction on separate code paths.
    static func batchClient(
        for route: ASRProviderRoute,
        defaults: UserDefaults = .standard,
        session: URLSession = .shared,
        profileProvider: @escaping @Sendable () -> SpeechCaptureProfile = { .dictation },
        keyReader: @escaping KeyReader = { BYOKKeychain.read($0) }
    ) -> any TranscriptionAPI {
        switch route {
        case .openAI:
            return openAI(
                defaults: defaults, session: session,
                profileProvider: profileProvider, keyReader: keyReader)
        case .mimo:
            return mimo(
                defaults: defaults, session: session,
                profileProvider: profileProvider, keyReader: keyReader)
        case .gemini:
            return gemini(
                defaults: defaults, session: session,
                profileProvider: profileProvider, keyReader: keyReader)
        case .volcengineRealtime:
            return volcengineRealtime(
                defaults: defaults, session: session,
                profileProvider: profileProvider, keyReader: keyReader)
        case .customOpenAI:
            return customOpenAI(
                defaults: defaults, session: session,
                profileProvider: profileProvider, keyReader: keyReader)
        case .apple, .qwenASRFlashRealtime, .sensevoiceLocal, .qwen3LocalASR,
                .fireRedASR2AEDLocal, .funAsrNanoLocal:
            preconditionFailure("ASR route \(route) does not use a batch transcription client")
        }
    }

    static func openAI(
        defaults: UserDefaults = .standard,
        session: URLSession = .shared,
        profileProvider: @escaping @Sendable () -> SpeechCaptureProfile = { .dictation },
        keyReader: @escaping KeyReader = { BYOKKeychain.read($0) }
    ) -> DirectOpenAITranscriptionAPI {
        let effective = effectiveConfiguration(
            forProvider: "openai", defaults: defaults, keyReader: keyReader)
        return DirectOpenAITranscriptionAPI(
            baseURL: httpBaseURL(effective),
            session: session,
            hotwordsProvider: { ContextHotwordSettings.asrWeakPrompt() },   // 517: 词典 + 当次屏幕临时词
            profileProvider: profileProvider,
            modelProvider: { effective.model },
            apiKeyProvider: { effective.apiKey ?? "" })
    }

    static func mimo(
        defaults: UserDefaults = .standard,
        session: URLSession = .shared,
        profileProvider: @escaping @Sendable () -> SpeechCaptureProfile = { .dictation },
        keyReader: @escaping KeyReader = { BYOKKeychain.read($0) }
    ) -> DirectMimoTranscriptionAPI {
        let effective = effectiveConfiguration(
            forProvider: "mimo", defaults: defaults, keyReader: keyReader)
        return DirectMimoTranscriptionAPI(
            baseURL: httpBaseURL(effective),
            session: session,
            hotwordsProvider: { ContextHotwordSettings.asrWeakPrompt() },   // 517: 词典 + 当次屏幕临时词
            profileProvider: profileProvider,
            modelProvider: { effective.model },
            apiKeyProvider: { effective.apiKey ?? "" })
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
        let effective = effectiveConfiguration(
            forProvider: "gemini", defaults: defaults, keyReader: keyReader)
        return DirectGeminiTranscriptionAPI(
            baseURL: httpBaseURL(effective),
            session: session,
            hotwordsProvider: { ContextHotwordSettings.asrWeakPrompt() },   // 517: 词典 + 当次屏幕临时词
            profileProvider: profileProvider,
            modelProvider: { effective.model },
            apiKeyProvider: { effective.apiKey ?? "" })
    }

    static func customOpenAI(
        defaults: UserDefaults = .standard,
        session: URLSession = .shared,
        profileProvider: @escaping @Sendable () -> SpeechCaptureProfile = { .dictation },
        keyReader: @escaping KeyReader = { BYOKKeychain.read($0) }
    ) -> DirectOpenAITranscriptionAPI {
        let effective = effectiveConfiguration(
            forProvider: "custom", defaults: defaults, keyReader: keyReader)
        return DirectOpenAITranscriptionAPI(
            baseURL: httpBaseURL(effective),
            session: session,
            hotwordsProvider: { ContextHotwordSettings.asrWeakPrompt() },   // 517: 词典 + 当次屏幕临时词
            profileProvider: profileProvider,
            modelProvider: { effective.model },
            apiKeyProvider: { effective.apiKey ?? "" })
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
        let effective = effectiveConfiguration(
            forProvider: "volcengine-flash", defaults: defaults, keyReader: keyReader)
        return VolcengineRealtimeTranscriptionAPI(
            endpoint: VolcengineRealtimeEndpoint(apiKey: effective.apiKey ?? ""),
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
    /// DashScope host. `ProviderConfigDispatcher` resolves the effective endpoint inputs, model and
    /// credential; this capture-time adapter applies the current scene and transient vocabulary.
    /// Stable synchronized terms use a bound `vocabulary_id`, while any local or per-capture delta
    /// uses the complete request-level `vocabulary` instead.
    ///
    /// Resolved fresh per capture (the capture service calls this in `start()`), so a provider /
    /// region / Workspace / model / key change takes effect without an app restart.
    static func qwenRunTaskConfig(
        defaults: UserDefaults = .standard,
        context: [String] = [],
        contextScope: String? = nil,
        keyReader: @escaping KeyReader = { BYOKKeychain.read($0) }
    ) -> QwenRunTaskCaptureConfig {
        let effective = effectiveConfiguration(
            forProvider: QwenASRFlashRouting.providerId,
            defaults: defaults,
            keyReader: keyReader)
        let endpoint = QwenASRFlashRouting.endpoint(
            workspaceID: effective.workspaceID,
            region: effective.region)
        let persistentHotwords = ContextHotwordSettings.qwenPersistentHotwords(defaults: defaults)
        let requestHotwords = ContextHotwordSettings.asrWeakPrompt(defaults: defaults)
        let fingerprint = QwenPrecompiledVocabularySettings.fingerprint(
            terms: persistentHotwords,
            model: effective.model)
        let resolvedIdentifier = QwenPrecompiledVocabularySettings.binding(defaults: defaults)?
            .resolvedIdentifier(
                model: effective.model,
                endpoint: endpoint,
                vocabularyFingerprint: fingerprint)
        let persistentVocabulary = QwenASRHotwords.vocabulary(
            from: persistentHotwords,
            model: effective.model)
        let requestVocabulary = QwenASRHotwords.vocabulary(
            from: requestHotwords,
            model: effective.model)
        let shouldUsePrecompiled = endpoint.supportsHotwords
            && resolvedIdentifier != nil
            && requestVocabulary == persistentVocabulary

        return QwenRunTaskCaptureConfig(
            endpoint: endpoint,
            apiKey: effective.apiKey ?? "",
            model: effective.model,
            hotwords: endpoint.supportsHotwords && !shouldUsePrecompiled ? requestHotwords : [],
            precompiledVocabularyID: shouldUsePrecompiled ? resolvedIdentifier : nil,
            context: context,
            contextScope: contextScope,
            heartbeat: true)
    }

    /// Resolve once when a capture starts. Every client closure captures this Sendable value, so
    /// a settings change while recording cannot combine the old endpoint with a new model, plan,
    /// or credential. `CloudQwenSpeechCaptureService.start()` rebuilds the client for the next
    /// capture, where the newly selected state then takes effect.
    private static func effectiveConfiguration(
        forProvider providerID: String,
        defaults: UserDefaults,
        keyReader: @escaping KeyReader
    ) -> ResolvedProviderConfig {
        ProviderConfigDispatcher(defaults: defaults, keyReader: keyReader)
            .resolve(.asr, providerId: providerID)
    }

    /// Invalid custom settings fail closed to a local non-network URL. Normal routing checks the
    /// effective configuration's endpoint before constructing a cloud client, but direct callers
    /// must still never fall back to a real provider and send a custom credential there.
    private static func httpBaseURL(_ effective: ResolvedProviderConfig) -> URL {
        guard let components = URLComponents(string: effective.baseURL),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil,
              let url = components.url else {
            return URL(fileURLWithPath: "/invalid-asr-endpoint")
        }
        return url
    }
}
