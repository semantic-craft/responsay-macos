import Foundation
import ResponsayCore
import ResponsaySpeech

@MainActor
final class RoutedSpeechCaptureService: SpeechCaptureService {
    private let defaults: UserDefaults
    private let cloudIsReady: (ASREngine) -> Bool
    private let apple: any SpeechCaptureService
    /// Internal seam for the six cloud adapters. Callers and tests still use only the router's
    /// `SpeechCaptureService` interface; production owns provider-specific construction here.
    private let cloudAdapterForRoute: (ASRProviderRoute) -> any SpeechCaptureService
    private let hotwordCorrector: SettingsBackedHotwordCorrectionAPI
    /// In-process offline ASR — runs SenseVoice locally, bypassing the backend.
    private let sensevoiceLocal = OfflineSherpaCaptureService(spec: .senseVoiceSmall) {
        try SenseVoiceModel.loadRecognizer()
    }
    /// In-process offline ASR — Qwen3-ASR (multilingual + Chinese/dialect strong). The one offline
    /// engine on the biasing flywheel: its model-config `hotwords` field is fed `weakPrompt` (#500
    /// S1), read fresh at each recognizer build (the `makeRecognizer` closure runs per TTL rebuild),
    /// so newly-learned terms reach it without an app restart.
    private let qwen3LocalASR = OfflineSherpaCaptureService(spec: .qwen3ASR) {
        try Qwen3ASRRecognizer(
            modelDir: LocalModelSpec.qwen3ASR.storagePath,
            hotwords: Qwen3ASRRecognizer.hotwordsString(from: ContextHotwordSettings.biasingSets().weakPrompt))
    }
    /// In-process offline ASR — FireRedASR2 AED (higher-quality Chinese/English + dialects).
    private let fireRedASR2AEDLocal = OfflineSherpaCaptureService(spec: .fireRedASR2AED) {
        try FireRedASR2AEDRecognizer(modelDir: LocalModelSpec.fireRedASR2AED.storagePath)
    }
    /// In-process offline ASR — Fun-ASR Nano (Alibaba, LLM-based, broad dialect coverage).
    private let funAsrNanoLocal = OfflineSherpaCaptureService(spec: .funAsrNano) {
        try FunASRNanoRecognizer(modelDir: LocalModelSpec.funAsrNano.storagePath)
    }
    private var active: SpeechCaptureService?
    private var captureProfile: SpeechCaptureProfile = .dictation

    private(set) var levels: AsyncStream<Float> = AsyncStream { _ in }

    convenience init(contextScopeProvider: @escaping @MainActor () -> String? = { nil }) {
        self.init(
            contextScopeProvider: contextScopeProvider,
            defaults: .standard,
            keyReader: { BYOKKeychain.read($0) },
            qwenRunTask: QwenRunTaskSession(),
            qwenAudioRecorder: { AVCaptureAudioRecorder() },
            qwenContextStore: .shared,
            requireQwenMicPermission: {
                try MicrophonePermission.ensure(feature: "Qwen ASR realtime")
            })
    }

    init(
        contextScopeProvider: @escaping @MainActor () -> String?,
        defaults: UserDefaults,
        keyReader: @escaping ASRTranscriptionClientFactory.KeyReader,
        qwenRunTask: any QwenRunTaskTranscribing,
        qwenAudioRecorder: @escaping () -> any SpeechAudioRecording,
        qwenContextStore: RecentASRContextSessionStore,
        requireQwenMicPermission: @escaping () throws -> Void
    ) {
        self.defaults = defaults
        let dispatcher = ProviderConfigDispatcher(defaults: defaults, keyReader: keyReader)
        let readiness = ModelLaneReadinessResolver(dispatcher: dispatcher)
        cloudIsReady = { readiness.asr(optionId: $0.rawValue).isReady }
        apple = AppleSpeechCaptureService()
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
                return ASRTranscriptionClientFactory.qwenRunTaskConfig(
                    defaults: defaults,
                    context: qwenContextStore.context(for: scope),
                    contextScope: scope,
                    keyReader: keyReader)
            },
            runTask: qwenRunTask,
            audioRecorder: qwenAudioRecorder,
            contextRecorder: { text, scope in
                qwenContextStore.record(text, scope: scope)
            },
            requireMicPermission: requireQwenMicPermission)
        cloudAdapterForRoute = { route in
            if route == .qwenASRFlashRealtime { return qwenASRFlashRealtime }

            let provider: String
            let permissionFeature: String
            switch route {
            case .openAI:
                provider = "openai"
                permissionFeature = "cloud ASR"
            case .mimo:
                provider = "mimo"
                permissionFeature = "cloud ASR"
            case .gemini:
                provider = "gemini"
                permissionFeature = "cloud ASR"
            case .volcengineRealtime:
                provider = "volcengine-realtime"
                permissionFeature = "Volcengine BigASR streaming"
            case .customOpenAI:
                provider = "custom"
                permissionFeature = "cloud ASR"
            case .apple, .qwenASRFlashRealtime, .sensevoiceLocal, .qwen3LocalASR,
                    .fireRedASR2AEDLocal, .funAsrNanoLocal:
                preconditionFailure("ASR route \(route) does not use a batch cloud adapter")
            }
            return CloudQwenSpeechCaptureService(
                provider: provider,
                requireMicPermission: {
                    try MicrophonePermission.ensure(feature: permissionFeature)
                },
                clientBuilder: { profile in
                    ASRTranscriptionClientFactory.batchClient(
                        for: route,
                        defaults: defaults,
                        profileProvider: profile,
                        keyReader: keyReader)
                })
        }
    }

    /// Deterministic internal seam for router-interface tests. Production callers use the
    /// convenience initializer above and cannot supply or observe provider construction.
    init(
        defaults: UserDefaults,
        cloudIsReady: @escaping (ASREngine) -> Bool,
        appleAdapter: any SpeechCaptureService,
        cloudAdapterForRoute: @escaping (ASRProviderRoute) -> any SpeechCaptureService
    ) {
        self.defaults = defaults
        self.cloudIsReady = cloudIsReady
        self.apple = appleAdapter
        self.cloudAdapterForRoute = cloudAdapterForRoute
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
        let selected = ASREngine.selected(defaults: defaults)
        let service = resolveService(selected: selected)

        (service as? SpeechCaptureProfileConfigurable)?
            .setCaptureProfile(captureProfile)
        Diag.asr(.info, "capture start",
                 fields: ["engine": selected.title, "locale": locale.rawValue])
        do {
            try service.start(locale: locale)
        } catch {
            Diag.asr(.error, "capture start failed",
                     fields: ["engine": selected.title], error: error.localizedDescription)
            throw error
        }
        active = service
        levels = service.levels
        // 517 — harvest visible-screen proper nouns as this capture's transient weak-prompt bias
        // (真·屏幕感知辅助识别). Synchronous return + detached task: the Fn→录音 hot path never
        // waits on AX; gated inside on the 屏幕上下文 master switch.
        TransientScreenTerms.beginHarvest()
    }

    /// Pick the concrete capture service from the user's explicit engine choice.
    ///
    /// Privacy posture (PRIV-CLOUD-001, 2026-06-14 decision — document, don't reroute): cloud
    /// vs local here is the user's *explicit* engine selection, never a silent escalation — a
    /// local engine failure throws and never falls back to cloud. Truly sensitive surfaces
    /// (password/secure-input fields, deny-listed apps/URLs) are blocked upstream by the
    /// CaptureGate before any engine runs, so no routing change is made for sensitive content.
    ///
    /// Per-scenario auto-routing (087 item 1) was retired by decision (issue 293,
    /// 2026-06-11): the engine roster had just been collapsed to explicit,
    /// user-language choices, and auto-switching providers per scenario would
    /// vary hotword behavior unpredictably. `CaptureProviderResolver` + tests
    /// deleted; recover from git history if the idea returns.
    private func resolveService(selected: ASREngine) -> SpeechCaptureService {
        // Always-usable fallback (#389): if the selected engine isn't ready (cloud
        // missing key / offline model not downloaded), transcribe via Apple for this
        // capture without mutating the stored selection. Non-blocking — never throws.
        let route = ASRProviderRoute.dictation(
            selected: selected,
            cloudHasKey: cloudIsReady)
        if route != ASRProviderRoute.from(engine: selected) {
            Diag.asr(.info, "selected engine not ready — using Apple for this capture",
                     fields: ["selected": selected.title])
        }
        switch route {

        case .apple:
            return apple
        case .openAI, .mimo, .gemini, .qwenASRFlashRealtime, .volcengineRealtime,
                .customOpenAI:
            return cloudAdapterForRoute(route)
        case .sensevoiceLocal:
            return sensevoiceLocal
        case .qwen3LocalASR:
            return qwen3LocalASR
        case .fireRedASR2AEDLocal:
            return fireRedASR2AEDLocal
        case .funAsrNanoLocal:
            return funAsrNanoLocal
        }
    }

    func stop() async throws -> String {
        guard let active else { return "" }
        defer { self.active = nil }
        let transcript = try await active.stop()
        // Post-ASR pipeline (ADR-0011), the one seam every provider funnels through — now gated by the
        // active engine's declared capability. The biasing-list echo guard runs ONLY for engines that
        // inject the weak hint as text (cloud multimodal); an on-device transcript that is legitimately
        // a term-list ("Westlaw, SSRN") is no longer mis-dropped. Hard-match stays universal. The pure
        // decision lives in SpeechTranscriptFinalizer (unit-tested, no mic/network).
        // 517: the echo check uses the SAME augmented list the request sent (dictionary + transient
        // screen terms), else an echo of the transient terms slips through (the 1.3.29 bug class).
        let sets = ContextHotwordSettings.biasingSets(defaults: defaults)
        let weakTerms = sets.weakPrompt(augmentedWith: TransientScreenTerms.current)
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

    /// #500 S3 — settings-gated, default-off LLM correction pass applied after the hard-match.
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
