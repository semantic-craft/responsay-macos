import Foundation
import ResponsayCore
import ResponsaySpeech

@MainActor
final class RoutedSpeechCaptureService: SpeechCaptureService {
    private let defaults: UserDefaults
    private let isReady: (ASREngine) -> Bool
    /// Internal adapter seam for every dictation engine. Callers and tests still use only the
    /// router's `SpeechCaptureService` interface; production owns engine construction here.
    private let adapterForEngine: (ASREngine) -> any SpeechCaptureService
    private let beginScreenTermHarvest: () -> Void
    private let screenTerms: TransientScreenTerms
    private let captureRequestEchoTerms: CaptureRequestEchoTerms
    private let hotwordCorrector: SettingsBackedHotwordCorrectionAPI
    private var active: SpeechCaptureService?
    private var captureProfile: SpeechCaptureProfile = .dictation

    private(set) var levels: AsyncStream<Float> = AsyncStream { _ in }

    convenience init(
        contextScopeProvider: @escaping @MainActor () -> String? = { nil },
        screenTermHarvester: @escaping (TransientScreenTerms) -> Void
    ) {
        self.init(
            contextScopeProvider: contextScopeProvider,
            defaults: .standard,
            keyReader: { BYOKKeychain.read($0) },
            qwenRunTask: QwenRunTaskSession(),
            qwenAudioRecorder: { AVCaptureAudioRecorder() },
            qwenContextStore: .shared,
            requireQwenMicPermission: {
                try MicrophonePermission.ensure(feature: "Qwen ASR realtime")
            },
            screenTermHarvester: screenTermHarvester)
    }

    init(
        contextScopeProvider: @escaping @MainActor () -> String?,
        defaults: UserDefaults,
        keyReader: @escaping ASRKeyReader,
        qwenRunTask: any QwenRunTaskTranscribing,
        qwenAudioRecorder: @escaping () -> any SpeechAudioRecording,
        qwenContextStore: RecentASRContextSessionStore,
        requireQwenMicPermission: @escaping () throws -> Void,
        screenTermHarvester: ((TransientScreenTerms) -> Void)? = nil,
        appleCaptureService: (any SpeechCaptureService)? = nil,
        localModelInstalled: @escaping @Sendable (LocalModelSpec) -> Bool = { $0.isInstalled },
        batchSession: URLSession = .shared,
        batchWebSocketTask: (@Sendable (URLRequest) -> URLSessionWebSocketTask)? = nil,
        batchAudioRecorder: @escaping () -> any SpeechAudioRecording = {
            AVCaptureAudioRecorder()
        },
        requireBatchMicPermission: @escaping (ASREngine) throws -> Void = { engine in
            let feature = engine == .cloudVolcengineRealtime
                ? "Volcengine BigASR streaming"
                : "cloud ASR"
            try MicrophonePermission.ensure(feature: feature)
        }
    ) {
        self.defaults = defaults
        let screenTerms = TransientScreenTerms()
        self.screenTerms = screenTerms
        if let screenTermHarvester {
            beginScreenTermHarvest = { screenTermHarvester(screenTerms) }
        } else {
            beginScreenTermHarvest = {
                screenTerms.beginHarvest(isEnabled: false)
            }
        }
        let requestEchoTerms = CaptureRequestEchoTerms()
        let sendableDefaults = CaptureUserDefaults(defaults)
        captureRequestEchoTerms = requestEchoTerms
        let dispatcher = ProviderConfigDispatcher(defaults: defaults, keyReader: keyReader)
        let readiness = ModelLaneReadinessResolver(dispatcher: dispatcher)
        isReady = { readiness.asr(optionId: $0.rawValue).isReady }
        let apple = appleCaptureService ?? AppleSpeechCaptureService()
        let sensevoiceLocal = OfflineSherpaCaptureService(
            spec: .senseVoiceSmall,
            isModelInstalled: { localModelInstalled(.senseVoiceSmall) }) {
            try SenseVoiceModel.loadRecognizer()
        }
        // Qwen3-ASR reads the weak-prompt hotwords on each recognizer rebuild, so newly learned
        // terms reach the downloadable engine without an app restart.
        let qwen3LocalASR = OfflineSherpaCaptureService(
            spec: .qwen3ASR,
            isModelInstalled: { localModelInstalled(.qwen3ASR) }) {
            try Qwen3ASRRecognizer(
                modelDir: LocalModelSpec.qwen3ASR.storagePath,
                hotwords: Qwen3ASRRecognizer.hotwordsString(
                    from: ContextHotwordSettings.biasingSets(
                        defaults: sendableDefaults.value).weakPrompt))
        }
        let funAsrNanoLocal = OfflineSherpaCaptureService(
            spec: .funAsrNano,
            isModelInstalled: { localModelInstalled(.funAsrNano) }) {
            try FunASRNanoRecognizer(modelDir: LocalModelSpec.funAsrNano.storagePath)
        }
        hotwordCorrector = SettingsBackedHotwordCorrectionAPI(
            isEnabled: { HotwordLLMCorrectionSettings.isEnabled(defaults: defaults) },
            resolveEndpoint: {
                LLMEndpointResolver.resolveText(
                    defaults: defaults,
                    dispatcher: dispatcher)
            })
        let qwenASRFlashRealtime = QwenRunTaskStreamingCaptureService(
            configProvider: {
                let scope = contextScopeProvider()
                let resolution = QwenRunTaskCaptureConfiguration.resolve(
                    defaults: defaults,
                    context: qwenContextStore.context(for: scope),
                    contextScope: scope,
                    keyReader: keyReader)
                return resolution.config
            },
            prepareConfig: { baseConfig in
                let transient = await screenTerms.awaitCurrentHarvest()
                try Task.checkCancellation()
                let config = QwenRunTaskCaptureConfiguration.augment(
                    baseConfig,
                    transientTerms: transient)
                requestEchoTerms.replace(config.effectiveEchoTerms)
                return config
            },
            runTask: qwenRunTask,
            audioRecorder: qwenAudioRecorder,
            contextRecorder: { text, scope in
                qwenContextStore.record(text, scope: scope)
            },
            requireMicPermission: requireQwenMicPermission)
        adapterForEngine = { engine in
            switch engine {
            case .apple:
                return apple
            case .cloudQwenASRFlashRealtime:
                return qwenASRFlashRealtime
            case .cloudOpenAI, .cloudMimo, .cloudGemini, .cloudVolcengineRealtime,
                    .customOpenAI:
                guard let providerID = engine.associatedProviderId else {
                    preconditionFailure("Cloud engine \(engine) has no provider ID")
                }
                let provider = engine == .cloudVolcengineRealtime
                    ? "volcengine-realtime"
                    : providerID
                return CloudQwenSpeechCaptureService(
                    provider: provider,
                    requireMicPermission: {
                        try requireBatchMicPermission(engine)
                    },
                    audioRecorder: batchAudioRecorder,
                    clientBuilder: { profile in
                        Self.batchTranscriptionClient(
                            for: engine,
                            defaults: defaults,
                            session: batchSession,
                            webSocketTaskProvider: batchWebSocketTask,
                            profileProvider: profile,
                            keyReader: keyReader,
                            requestEchoTerms: requestEchoTerms,
                            screenTerms: screenTerms)
                    })
            case .sensevoiceLocal:
                return sensevoiceLocal
            case .qwen3LocalASR:
                return qwen3LocalASR
            case .funAsrNanoLocal:
                return funAsrNanoLocal
            }
        }
    }

    /// Deterministic internal seam for router-interface tests. Production callers use the
    /// convenience initializer above and cannot supply or observe adapter construction.
    init(
        defaults: UserDefaults,
        isReady: @escaping (ASREngine) -> Bool,
        adapterForEngine: @escaping (ASREngine) -> any SpeechCaptureService,
        screenTermHarvester: ((TransientScreenTerms) -> Void)? = nil
    ) {
        self.defaults = defaults
        self.isReady = isReady
        self.adapterForEngine = adapterForEngine
        let screenTerms = TransientScreenTerms()
        self.screenTerms = screenTerms
        if let screenTermHarvester {
            beginScreenTermHarvest = { screenTermHarvester(screenTerms) }
        } else {
            beginScreenTermHarvest = {
                screenTerms.beginHarvest(isEnabled: false)
            }
        }
        captureRequestEchoTerms = CaptureRequestEchoTerms()
        let dispatcher = ProviderConfigDispatcher(defaults: defaults, keyReader: { _ in nil })
        hotwordCorrector = SettingsBackedHotwordCorrectionAPI(
            isEnabled: { HotwordLLMCorrectionSettings.isEnabled(defaults: defaults) },
            resolveEndpoint: {
                LLMEndpointResolver.resolveText(defaults: defaults, dispatcher: dispatcher)
            })
    }

    /// Delegates to the resolved engine so callers see the ACTIVE engine's real capability
    /// (partials style, echo risk) rather than a router-level guess.
    var captureCapability: SpeechCaptureCapability {
        active?.captureCapability ?? .init()
    }

    func start(locale: CaptureLocale) throws {
        guard active == nil else {
            throw CoachAPIError.message("已有语音采集正在进行。")
        }
        let selected = ASREngine.selected(defaults: defaults)
        let service = resolveService(selected: selected)

        (service as? SpeechCaptureProfileConfigurable)?
            .setCaptureProfile(captureProfile)
        Diag.asr(.info, "capture start",
                 fields: ["engine": selected.title, "locale": locale.rawValue])
        // Establish a new per-router generation before the adapter starts. Qwen and Volc can wait
        // for this generation's bounded harvest decision while audio buffers, but the actual AX
        // read is not scheduled until the selected adapter has started successfully.
        screenTerms.prepareCapture()
        captureRequestEchoTerms.reset()
        do {
            try service.start(locale: locale)
        } catch {
            screenTerms.finishCapture()
            captureRequestEchoTerms.reset()
            Diag.asr(.error, "capture start failed",
                     fields: ["engine": selected.title], error: error.localizedDescription)
            throw error
        }
        active = service
        levels = service.levels
        // 517 — harvest visible-screen proper nouns as this capture's transient weak-prompt bias
        // (真·屏幕感知辅助识别). Synchronous return + detached task: the Fn→录音 hot path never
        // waits on AX; the production caller supplies both the target process and CaptureGate.
        beginScreenTermHarvest()
    }

    /// Pick the concrete capture service from the user's explicit engine choice.
    ///
    /// Privacy posture (PRIV-CLOUD-001, 2026-06-14 decision — document, don't reroute): cloud
    /// vs local here is the user's *explicit* engine selection, never a silent escalation — a
    /// local engine failure throws and never falls back to cloud. CaptureGate separately blocks
    /// screen-derived context and hotword harvesting for password/secure-input fields and
    /// deny-listed apps/URLs; it does not change the user's explicit audio engine selection.
    ///
    /// Per-scenario auto-routing (087 item 1) was retired by decision (issue 293,
    /// 2026-06-11): the engine roster had just been collapsed to explicit,
    /// user-language choices, and auto-switching providers per scenario would
    /// vary hotword behavior unpredictably. `CaptureProviderResolver` + tests
    /// deleted; recover from git history if the idea returns.
    private func resolveService(selected: ASREngine) -> SpeechCaptureService {
        // Keep the explicit cloud readiness fallback from #81. Downloadable local engines remain
        // selected even while missing so their adapter reports the model-install error; they never
        // escape into an Apple recognizer that may itself use a server-side recognition path.
        let resolved = selected.associatedProviderId != nil && !isReady(selected)
            ? ASREngine.apple
            : selected
        if resolved != selected {
            Diag.asr(.info, "selected engine not ready — using Apple for this capture",
                     fields: ["selected": selected.title])
        }
        return adapterForEngine(resolved)
    }

    func stop() async throws -> String {
        guard let active else { return "" }
        defer {
            self.active = nil
            screenTerms.finishCapture()
            captureRequestEchoTerms.reset()
        }
        let transcript = try await active.stop()
        // Post-ASR pipeline (ADR-0011), the one seam every provider funnels through — now gated by the
        // active engine's declared capability. The biasing-list echo guard runs ONLY for engines that
        // inject the weak hint as text (cloud multimodal); an on-device transcript that is legitimately
        // a term-list ("Westlaw, SSRN") is no longer mis-dropped. Hard-match stays universal. The pure
        // decision lives in SpeechTranscriptFinalizer (unit-tested, no mic/network).
        // 517: the echo check uses the SAME augmented list the request sent (dictionary + transient
        // screen terms), else an echo of the transient terms slips through (the 1.3.29 bug class).
        let sets = ContextHotwordSettings.biasingSets(defaults: defaults)
        let weakTerms = captureRequestEchoTerms.value ?? sets.weakPrompt
        guard let enforced = SpeechTranscriptFinalizer.enforce(
            transcript, capability: active.captureCapability, sets: sets, echoTerms: weakTerms) else {
            Diag.asr(.info, "transcript dropped: hotword biasing-list echo")
            return ""
        }
        // #500 S3 — optional BYOK-LLM correction tier. DEFAULT OFF: an exact, zero-cost no-op unless
        // the user opted in, a key is configured, and a near-miss hotword survived the hard-match.
        // Advisory only — degrades to `enforced` on any failure or untrusted reply (ADR-0008).
        return await hotwordCorrector.correct(enforced, userTerms: sets.hardMatchUser)
    }

    private static func batchTranscriptionClient(
        for engine: ASREngine,
        defaults: UserDefaults,
        session: URLSession = .shared,
        webSocketTaskProvider: (@Sendable (URLRequest) -> URLSessionWebSocketTask)?,
        profileProvider: @escaping @Sendable () -> SpeechCaptureProfile,
        keyReader: @escaping ASRKeyReader,
        requestEchoTerms: CaptureRequestEchoTerms,
        screenTerms: TransientScreenTerms
    ) -> any TranscriptionAPI {
        guard let providerID = engine.associatedProviderId else {
            preconditionFailure("Batch cloud engine \(engine) has no provider ID")
        }
        let effective = ProviderConfigDispatcher(defaults: defaults, keyReader: keyReader)
            .resolve(.asr, providerId: providerID)
        let baseURL = httpBaseURL(effective)
        let sendableDefaults = CaptureUserDefaults(defaults)

        switch engine {
        case .cloudOpenAI, .customOpenAI:
            return DirectOpenAITranscriptionAPI(
                baseURL: baseURL,
                session: session,
                hotwordsProvider: {
                    requestEchoTerms.freeze(
                        ContextHotwordSettings.asrWeakPrompt(
                            defaults: sendableDefaults.value,
                            transientTerms: screenTerms.current))
                },
                profileProvider: profileProvider,
                modelProvider: { effective.model },
                apiKeyProvider: { effective.apiKey ?? "" })
        case .cloudMimo:
            requestEchoTerms.freeze([])
            return DirectMimoTranscriptionAPI(
                baseURL: baseURL,
                session: session,
                hotwordsProvider: { [] },
                profileProvider: profileProvider,
                modelProvider: { effective.model },
                apiKeyProvider: { effective.apiKey ?? "" })
        case .cloudGemini:
            return DirectGeminiTranscriptionAPI(
                baseURL: baseURL,
                session: session,
                hotwordsProvider: {
                    requestEchoTerms.freeze(
                        ContextHotwordSettings.asrWeakPrompt(
                            defaults: sendableDefaults.value,
                            transientTerms: screenTerms.current))
                },
                profileProvider: profileProvider,
                modelProvider: { effective.model },
                apiKeyProvider: { effective.apiKey ?? "" })
        case .cloudVolcengineRealtime:
            return VolcengineRealtimeTranscriptionAPI(
                endpoint: VolcengineRealtimeEndpoint(apiKey: effective.apiKey ?? ""),
                config: VolcengineRealtimeConfig(),
                hotwordsProvider: {
                    let transient = await screenTerms.awaitCurrentHarvest()
                    return requestEchoTerms.freeze(
                        ContextHotwordSettings.biasingSets(defaults: sendableDefaults.value)
                            .weakPrompt(augmentedWith: transient))
                },
                session: session,
                webSocketTaskProvider: webSocketTaskProvider)
        case .apple, .cloudQwenASRFlashRealtime, .sensevoiceLocal, .qwen3LocalASR,
                .funAsrNanoLocal:
            preconditionFailure("Engine \(engine) does not use batch cloud transcription")
        }
    }

    /// Invalid custom configuration fails closed to a local non-network URL. Normal readiness
    /// prevents this client from being selected, while this guard keeps construction safe too.
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

extension RoutedSpeechCaptureService: SpeechCaptureProfileConfigurable {
    func setCaptureProfile(_ profile: SpeechCaptureProfile) {
        captureProfile = profile
    }
}

extension RoutedSpeechCaptureService: SpeechPartialTranscriptProviding {
    /// Live partials from the engine the current capture resolved to. Final-only engines yield an immediately
    /// finished stream, so consumers' partial loops simply end. The router never
    /// conformed before, so the `as? SpeechPartialTranscriptProviding` casts in
    /// QuickCaptureViewModel/VoiceAssistantViewModel always failed — live capsule
    /// preview and streaming ASR direct-write were dead for every engine in
    /// production (猎虫① H11, issue 322).
    var partialTranscripts: AsyncStream<String> {
        (active as? SpeechPartialTranscriptProviding)?.partialTranscripts
            ?? AsyncStream { $0.finish() }
    }
}
