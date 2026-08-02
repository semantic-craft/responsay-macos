import Foundation
import ResponsayCore
import ResponsaySpeech

@MainActor
final class RoutedSpeechCaptureService: SpeechCaptureService {
    private let apple = AppleSpeechCaptureService()
    // 猎虫① H9: the batch clients are built through `clientBuilder` so the
    // hotword weak hint (ADR-0011 keeps it alongside hard-match) and the live
    // capture profile reach the request — both were silently dropped at the
    // app-direct migration (the old `client:` shape froze the `{ [] }` /
    // `.dictation` defaults forever).
    private let cloudOpenAI = CloudQwenSpeechCaptureService(provider: "openai", requireMicPermission: { try MicrophonePermission.ensure(feature: "cloud ASR") }) { profile in
        ASRTranscriptionClientFactory.openAI(profileProvider: profile)
    }
    private let cloudMimo = CloudQwenSpeechCaptureService(provider: "mimo", requireMicPermission: { try MicrophonePermission.ensure(feature: "cloud ASR") }) { profile in
        ASRTranscriptionClientFactory.mimo(profileProvider: profile)
    }
    /// Google Gemini 整段识别 — batch transcription via native :generateContent (BYOK-direct).
    private let cloudGemini = CloudQwenSpeechCaptureService(provider: "gemini", requireMicPermission: { try MicrophonePermission.ensure(feature: "cloud ASR") }) { profile in
        ASRTranscriptionClientFactory.gemini(profileProvider: profile)
    }
    /// 火山引擎大模型录音文件极速版 — final-only HTTP recognition via
    /// `volc.bigasr.auc_turbo`. No realtime partials; insertion waits for stop().
    private let cloudVolcengineFlash = CloudQwenSpeechCaptureService(provider: "volcengine-flash", requireMicPermission: { try MicrophonePermission.ensure(feature: "Volcengine BigASR flash") }) { profile in
        ASRTranscriptionClientFactory.volcengineFlash(profileProvider: profile)
    }
    /// 火山引擎大模型流式 — final-only over the `bigmodel_nostream` streaming socket (#580): record the
    /// clip, then on stop replay it over the WebSocket for one clean final (lower stop-to-final
    /// latency than the submit/query 录音文件 path). No live partials yet. Same 火山 key.
    private let cloudVolcengineRealtime = CloudQwenSpeechCaptureService(provider: "volcengine-realtime", requireMicPermission: { try MicrophonePermission.ensure(feature: "Volcengine BigASR streaming") }) { profile in
        ASRTranscriptionClientFactory.volcengineRealtime(profileProvider: profile)
    }
    /// 阿里云百炼 千问实时 — 实时语音识别 over the run-task WebSocket (#588): frames stream while the
    /// hotkey is held, `finish-task` on release returns the 整段 transcript. Replaced the
    /// OmniRealtime socket, which spoke a different protocol on the sibling `/api-ws/v1/realtime`
    /// path and whose only model (qwen3-asr-flash-realtime) supports no hotwords at all; this one
    /// takes the 词典 through 即时热词 `vocabulary`. Final-only on purpose — streaming is for latency,
    /// not for a live capsule preview.
    private let qwenASRFlashRealtime = QwenRunTaskStreamingCaptureService(
        configProvider: { ASRTranscriptionClientFactory.qwenRunTaskConfig() },
        requireMicPermission: { try MicrophonePermission.ensure(feature: "Qwen ASR realtime") })
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
    // 320: endpoint/model resolve from the credential card's keys (legacy
    // customASR* pair as fallback) — the「高级」fields were the only live
    // surface before, while the card's Base URL/Model were silently dead.
    private let customOpenAI = CloudQwenSpeechCaptureService(provider: "custom", requireMicPermission: { try MicrophonePermission.ensure(feature: "cloud ASR") }) { profile in
        ASRTranscriptionClientFactory.customOpenAI(profileProvider: profile)
    }
    private var active: SpeechCaptureService?
    private var captureProfile: SpeechCaptureProfile = .dictation

    private(set) var levels: AsyncStream<Float> = AsyncStream { _ in }

    /// Delegates to the resolved engine so callers see the ACTIVE engine's real capability
    /// (partials style, echo risk) rather than a router-level guess.
    var captureCapability: SpeechCaptureCapability {
        active?.captureCapability ?? .init()
    }

    func start(locale: CaptureLocale) throws {
        let service = resolveService()

        (service as? SpeechCaptureProfileConfigurable)?
            .setCaptureProfile(captureProfile)
        Diag.asr(.info, "capture start",
                 fields: ["engine": ASREngine.selected.title, "locale": locale.rawValue])
        do {
            try service.start(locale: locale)
        } catch {
            Diag.asr(.error, "capture start failed",
                     fields: ["engine": ASREngine.selected.title], error: error.localizedDescription)
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
    private func resolveService() -> SpeechCaptureService {
        // Always-usable fallback (#389): if the selected engine isn't ready (cloud
        // missing key / offline model not downloaded), transcribe via Apple for this
        // capture without mutating the stored selection. Non-blocking — never throws.
        let selected = ASREngine.selected
        let route = ASRProviderRoute.dictation(selected: selected)
        if route != ASRProviderRoute.from(engine: selected) {
            Diag.asr(.info, "selected engine not ready — using Apple for this capture",
                     fields: ["selected": selected.title])
        }
        switch route {

        case .apple:
            return apple
        case .openAI:
            return cloudOpenAI
        case .mimo:
            return cloudMimo
        case .gemini:
            return cloudGemini
        case .qwenASRFlashRealtime:
            return qwenASRFlashRealtime
        case .volcengineFlash:
            return cloudVolcengineFlash
        case .volcengineRealtime:
            return cloudVolcengineRealtime
        case .sensevoiceLocal:
            return sensevoiceLocal
        case .qwen3LocalASR:
            return qwen3LocalASR
        case .fireRedASR2AEDLocal:
            return fireRedASR2AEDLocal
        case .funAsrNanoLocal:
            return funAsrNanoLocal
        case .customOpenAI:
            return customOpenAI
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
        let sets = ContextHotwordSettings.biasingSets()
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
    private let hotwordCorrector = SettingsBackedHotwordCorrectionAPI()
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
