import AVFoundation
import ResponsayCore
@testable import ResponsaySpeech
import XCTest
@testable import ResponsayMac

private final class ASRCredentialStore: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    private var reads: [String] = []

    func read(_ account: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        reads.append(account)
        return values[account]
    }

    func write(_ value: String, account: String) {
        lock.lock()
        defer { lock.unlock() }
        values[account] = value
    }

    func resetReads() {
        lock.lock()
        defer { lock.unlock() }
        reads = []
    }

    var recordedReads: [String] {
        lock.lock()
        defer { lock.unlock() }
        return reads
    }
}

/// Local adapter for the two true external inputs in Qwen dictation: microphone audio and the
/// remote run-task exchange. The router and shipped capture adapter remain real; only hardware and
/// network are replaced.
private final class LocalQwenDictationAdapter: @unchecked Sendable,
    SpeechAudioRecording, QwenRunTaskTranscribing
{
    enum Completion: Sendable {
        case transcript(String)
        case timeout
        case taskFailure(String)
        case waitForCancellation
    }

    private let lock = NSLock()
    private let completion: Completion
    private var onBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?
    private var _started = false
    private var _stopped = false
    private var _waitingForCancellation = false
    private var _wasCancelled = false
    private var _config: QwenRunTaskCaptureConfig?
    private var _audio = [Data]()
    private var _callbackContext = [String]()

    init(completion: Completion = .transcript("推到代码厂里")) {
        self.completion = completion
    }

    var started: Bool { withLock { _started } }
    var stopped: Bool { withLock { _stopped } }
    var waitingForCancellation: Bool { withLock { _waitingForCancellation } }
    var wasCancelled: Bool { withLock { _wasCancelled } }
    var config: QwenRunTaskCaptureConfig? { withLock { _config } }
    var audio: [Data] { withLock { _audio } }
    var callbackContext: [String] { withLock { _callbackContext } }

    func start(
        preferredUID _: String,
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void
    ) throws {
        withLock {
            _started = true
            self.onBuffer = onBuffer
        }
    }

    func stop() {
        withLock {
            _stopped = true
            onBuffer = nil
        }
    }

    func deliver(_ samples: [Float]) {
        let format = AVCaptureAudioRecorder.deliveredFormat
        let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for (index, sample) in samples.enumerated() {
            buffer.floatChannelData![0][index] = sample
        }
        withLock { onBuffer }?(buffer)
    }

    func transcribe(
        config: QwenRunTaskCaptureConfig,
        audio: AsyncStream<Data>,
        onFinalSentence: @escaping @Sendable (String) async -> [String],
        onTaskStarted: @escaping @Sendable (QwenRunTaskStartMetric) async -> Void
    ) async throws -> String {
        withLock { _config = config }
        await onTaskStarted(.init(reusedConnection: false, runTaskToStartedNanos: 1_000_000))
        for await frame in audio {
            withLock { _audio.append(frame) }
        }
        let updatedContext = await onFinalSentence("前一段原始转写")
        withLock { _callbackContext = updatedContext }
        switch completion {
        case let .transcript(text):
            return text
        case .timeout:
            throw QwenRunTaskSessionError.taskResponseTimedOut
        case let .taskFailure(message):
            throw QwenRunTaskSessionError.taskFailed(message)
        case .waitForCancellation:
            withLock { _waitingForCancellation = true }
            do {
                try await Task.sleep(nanoseconds: 60_000_000_000)
                throw QwenRunTaskSessionError.taskResponseTimedOut
            } catch is CancellationError {
                withLock { _wasCancelled = true }
                throw CancellationError()
            }
        }
    }

    private func withLock<Value>(_ body: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

@MainActor
private final class DeterministicCloudDictationAdapter: SpeechCaptureService,
    SpeechPartialTranscriptProviding
{
    private let result: String
    private let level: Float
    private let partial: String?
    let captureCapability: SpeechCaptureCapability
    private var isCapturing = false

    private(set) var levels: AsyncStream<Float> = AsyncStream { $0.finish() }
    private(set) var partialTranscripts: AsyncStream<String> = AsyncStream { $0.finish() }

    init(
        result: String,
        level: Float,
        partial: String?,
        capability: SpeechCaptureCapability
    ) {
        self.result = result
        self.level = level
        self.partial = partial
        self.captureCapability = capability
    }

    func start(locale _: CaptureLocale) throws {
        isCapturing = true
        levels = AsyncStream { continuation in
            continuation.yield(level)
            continuation.finish()
        }
        partialTranscripts = AsyncStream { continuation in
            if let partial { continuation.yield(partial) }
            continuation.finish()
        }
    }

    func stop() async throws -> String {
        guard isCapturing else { throw DeterministicCloudDictationError.stopBeforeStart }
        isCapturing = false
        return result
    }
}

private enum DeterministicCloudDictationError: Error {
    case stopBeforeStart
}

/// 猎虫① H11 (issue 322): the router never conformed to
/// `SpeechPartialTranscriptProviding`, so the `as?` casts in
/// QuickCaptureViewModel / VoiceAssistantViewModel always failed — live capsule
/// preview and streaming ASR direct-write were dead for every engine in
/// production, while tests passed by injecting conforming mocks directly.
/// These tests pin the conformance at the router seam itself.
final class RoutedSpeechCaptureServiceTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "routed-asr-runtime-tests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    @MainActor
    func testRouterProvidesPartialTranscripts() {
        let router: SpeechCaptureService = RoutedSpeechCaptureService()
        XCTAssertNotNil(
            router as? SpeechPartialTranscriptProviding,
            "router must forward partials or the VM-side streaming path is dead for all engines")
    }

    @MainActor
    func testPartialStreamWithoutActiveCaptureFinishesImmediately() async {
        let router = RoutedSpeechCaptureService()
        var received = [String]()
        // No capture started → the fallback stream must finish at once
        // (a hang here would wedge the VM's partial task).
        for await text in router.partialTranscripts {
            received.append(text)
        }
        XCTAssertTrue(received.isEmpty)
    }

    @MainActor
    func testEveryCloudSelectionRunsItsAdapterThroughTheRouterInterface() async throws {
        let cases: [(engine: ASREngine, result: String, level: Float,
                     partial: String?, capability: SpeechCaptureCapability)] = [
            (.cloudOpenAI, "openai final", 0.11, "openai partial",
             .init(partialStyle: .postUploadSSE, needsEchoFilter: true)),
            (.cloudMimo, "mimo final", 0.22, "mimo partial",
             .init(partialStyle: .postUploadSSE, needsEchoFilter: true)),
            (.cloudGemini, "gemini final", 0.33, "gemini partial",
             .init(partialStyle: .postUploadSSE, needsEchoFilter: true)),
            (.cloudQwenASRFlashRealtime, "qwen final", 0.44, nil,
             .init(partialStyle: .none, needsEchoFilter: true)),
            (.cloudVolcengineRealtime, "volcengine final", 0.55, nil,
             .init(partialStyle: .none, needsEchoFilter: true)),
            (.customOpenAI, "custom final", 0.66, "custom partial",
             .init(partialStyle: .postUploadSSE, needsEchoFilter: true)),
        ]

        for testCase in cases {
            defaults.set(testCase.engine.rawValue, forKey: ASREngine.defaultsKey)
            let router = RoutedSpeechCaptureService(
                defaults: defaults,
                cloudIsReady: { _ in true },
                appleAdapter: DeterministicCloudDictationAdapter(
                    result: "apple fallback", level: 0.99, partial: nil,
                    capability: .init()),
                cloudAdapter: { route in Self.deterministicAdapter(for: route) })

            try router.start(locale: .mixed)

            var levels = [Float]()
            for await level in router.levels { levels.append(level) }
            var partials = [String]()
            for await partial in router.partialTranscripts { partials.append(partial) }
            XCTAssertEqual(router.captureCapability, testCase.capability, testCase.engine.rawValue)
            let final = try await router.stop()

            XCTAssertEqual(levels, [testCase.level], testCase.engine.rawValue)
            XCTAssertEqual(partials, testCase.partial.map { [$0] } ?? [], testCase.engine.rawValue)
            XCTAssertEqual(final, testCase.result, testCase.engine.rawValue)
        }
    }

    @MainActor
    func testUnreadyCloudSelectionUsesExplicitAppleFallbackWithoutChangingSelection() async throws {
        defaults.set(ASREngine.cloudGemini.rawValue, forKey: ASREngine.defaultsKey)
        let router = RoutedSpeechCaptureService(
            defaults: defaults,
            cloudIsReady: { _ in false },
            appleAdapter: DeterministicCloudDictationAdapter(
                result: "apple fallback", level: 0.77, partial: nil,
                capability: .init()),
            cloudAdapter: { route in Self.deterministicAdapter(for: route) })

        try router.start(locale: .english)
        var levels = [Float]()
        for await level in router.levels { levels.append(level) }
        let final = try await router.stop()

        XCTAssertEqual(levels, [0.77])
        XCTAssertEqual(final, "apple fallback")
        XCTAssertEqual(defaults.string(forKey: ASREngine.defaultsKey), ASREngine.cloudGemini.rawValue)
        XCTAssertEqual(ASREngine.selected(defaults: defaults), .cloudGemini)
    }

    @MainActor
    func testCloudFinalResultUsesTheRouterFinalizationPipeline() async throws {
        defaults.set(ASREngine.cloudOpenAI.rawValue, forKey: ASREngine.defaultsKey)
        XCTAssertTrue(ContextHotwordSettings.addManual("代码仓", defaults: defaults))
        let router = RoutedSpeechCaptureService(
            defaults: defaults,
            cloudIsReady: { _ in true },
            appleAdapter: DeterministicCloudDictationAdapter(
                result: "apple fallback", level: 0.77, partial: nil,
                capability: .init()),
            cloudAdapter: { _ in
                DeterministicCloudDictationAdapter(
                    result: "推到代码厂里", level: 0.11, partial: "推到代码",
                    capability: .init(partialStyle: .postUploadSSE, needsEchoFilter: true))
            })

        try router.start(locale: .mixed)

        let final = try await router.stop()
        XCTAssertEqual(final, "推到代码仓里")
    }

    @MainActor
    private static func deterministicAdapter(
        for route: ASRProviderRoute
    ) -> DeterministicCloudDictationAdapter {
        switch route {
        case .openAI:
            DeterministicCloudDictationAdapter(
                result: "openai final", level: 0.11, partial: "openai partial",
                capability: .init(partialStyle: .postUploadSSE, needsEchoFilter: true))
        case .mimo:
            DeterministicCloudDictationAdapter(
                result: "mimo final", level: 0.22, partial: "mimo partial",
                capability: .init(partialStyle: .postUploadSSE, needsEchoFilter: true))
        case .gemini:
            DeterministicCloudDictationAdapter(
                result: "gemini final", level: 0.33, partial: "gemini partial",
                capability: .init(partialStyle: .postUploadSSE, needsEchoFilter: true))
        case .qwenASRFlashRealtime:
            DeterministicCloudDictationAdapter(
                result: "qwen final", level: 0.44, partial: nil,
                capability: .init(partialStyle: .none, needsEchoFilter: true))
        case .volcengineRealtime:
            DeterministicCloudDictationAdapter(
                result: "volcengine final", level: 0.55, partial: nil,
                capability: .init(partialStyle: .none, needsEchoFilter: true))
        case .customOpenAI:
            DeterministicCloudDictationAdapter(
                result: "custom final", level: 0.66, partial: "custom partial",
                capability: .init(partialStyle: .postUploadSSE, needsEchoFilter: true))
        case .apple, .sensevoiceLocal, .qwen3LocalASR, .fireRedASR2AEDLocal, .funAsrNanoLocal:
            preconditionFailure("non-cloud route cannot build a cloud adapter")
        }
    }

    @MainActor
    func testSelectedQwenCaptureRunsEndToEndThroughProductionRouter() async throws {
        ModelRouteSelectionActions.applyASRSelection(
            ASREngine.cloudQwenASRFlashRealtime.rawValue,
            defaults: defaults)
        defaults.set(QwenASRFlashRouting.providerId, forKey: "byok.asr.provider")
        defaults.set(
            ProviderRegion.singapore.rawValue,
            forKey: "byok.asr.qwen-asr-flash.region")
        defaults.set(
            "ws-localadapter",
            forKey: "byok.asr.qwen-asr-flash.workspaceId")
        defaults.set(
            QwenASRFlashRouting.funASRRealtimeModel,
            forKey: "byok.asr.qwen-asr-flash.model")
        XCTAssertTrue(ContextHotwordSettings.addManual("代码仓", defaults: defaults))

        let adapter = LocalQwenDictationAdapter()
        let contextStore = RecentASRContextSessionStore(
            defaults: defaults,
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("qwen-route-\(UUID().uuidString).json"))
        let router = RoutedSpeechCaptureService(
            contextScopeProvider: { "com.example.Editor" },
            defaults: defaults,
            keyReader: { account in
                account == CapabilityCredentialAccount.apiKeyAccount(
                    providerId: QwenASRFlashRouting.providerId,
                    capability: .asr,
                    plan: .payg)
                    ? "synthetic-qwen-key"
                    : nil
            },
            qwenRunTask: adapter,
            qwenAudioRecorder: { adapter },
            qwenContextStore: contextStore,
            requireQwenMicPermission: {})

        try router.start(locale: .mixed)
        let level = Task { @MainActor in
            for await value in router.levels { return value }
            return -1
        }
        adapter.deliver([0, 1, -1])
        let transcript = try await router.stop()
        let observedLevel = await level.value

        XCTAssertTrue(adapter.started)
        XCTAssertTrue(adapter.stopped)
        XCTAssertEqual(observedLevel, 1, accuracy: 0.001)
        XCTAssertEqual(adapter.audio, [Data([0x00, 0x00, 0xff, 0x7f, 0x01, 0x80])])
        XCTAssertEqual(adapter.config?.captureLocale, .mixed)
        XCTAssertEqual(adapter.config?.apiKey, "synthetic-qwen-key")
        XCTAssertEqual(adapter.config?.model, QwenASRFlashRouting.funASRRealtimeModel)
        XCTAssertEqual(
            adapter.config?.endpoint.url.absoluteString,
            "wss://ws-localadapter.ap-southeast-1.maas.aliyuncs.com/api-ws/v1/inference")
        XCTAssertEqual(adapter.callbackContext, ["前一段原始转写"])
        XCTAssertEqual(transcript, "推到代码仓里")
    }

    @MainActor
    func testQwenTimeoutIsObservableAtProductionRouter() async throws {
        let adapter = LocalQwenDictationAdapter(completion: .timeout)
        let router = makeQwenRouter(adapter: adapter)

        try router.start(locale: .mixed)
        do {
            _ = try await router.stop()
            XCTFail("timeout must not be collapsed into an empty transcript")
        } catch QwenRunTaskSessionError.taskResponseTimedOut {
            XCTAssertTrue(adapter.stopped)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    @MainActor
    func testQwenTaskFailureIsObservableAtProductionRouter() async throws {
        let adapter = LocalQwenDictationAdapter(
            completion: .taskFailure("synthetic run-task failure"))
        let router = makeQwenRouter(adapter: adapter)

        try router.start(locale: .mixed)
        do {
            _ = try await router.stop()
            XCTFail("task failure must not be collapsed into an empty transcript")
        } catch let QwenRunTaskSessionError.taskFailed(message) {
            XCTAssertEqual(message, "synthetic run-task failure")
            XCTAssertTrue(adapter.stopped)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    @MainActor
    func testQwenCancellationIsObservableAtProductionRouter() async throws {
        let adapter = LocalQwenDictationAdapter(completion: .waitForCancellation)
        let router = makeQwenRouter(adapter: adapter)

        try router.start(locale: .mixed)
        let stopTask = Task { @MainActor in try await router.stop() }
        for _ in 0 ..< 10_000 where !adapter.waitingForCancellation {
            await Task.yield()
        }
        guard adapter.waitingForCancellation else {
            stopTask.cancel()
            return XCTFail("local run-task adapter never reached its cancellation wait")
        }

        stopTask.cancel()
        do {
            _ = try await stopTask.value
            XCTFail("cancellation must not be collapsed into an empty transcript")
        } catch is CancellationError {
            XCTAssertTrue(adapter.wasCancelled)
            XCTAssertTrue(adapter.stopped)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    @MainActor
    private func makeQwenRouter(adapter: LocalQwenDictationAdapter) -> RoutedSpeechCaptureService {
        ModelRouteSelectionActions.applyASRSelection(
            ASREngine.cloudQwenASRFlashRealtime.rawValue,
            defaults: defaults)
        let contextStore = RecentASRContextSessionStore(
            defaults: defaults,
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("qwen-route-\(UUID().uuidString).json"))
        return RoutedSpeechCaptureService(
            contextScopeProvider: { "com.example.Editor" },
            defaults: defaults,
            keyReader: { account in
                account == CapabilityCredentialAccount.apiKeyAccount(
                    providerId: QwenASRFlashRouting.providerId,
                    capability: .asr,
                    plan: .payg)
                    ? "synthetic-qwen-key"
                    : nil
            },
            qwenRunTask: adapter,
            qwenAudioRecorder: { adapter },
            qwenContextStore: contextStore,
            requireQwenMicPermission: {})
    }

    /// The 千问 card dials the run-task socket. Without a Workspace ID it must keep using the
    /// generic DashScope host, and it must read only the current `byok.qwen-asr-flash` slot.
    func testQwenRunTaskWithoutWorkspaceUsesGenericHostAndCurrentKeySlot() {
        defaults.set("qwen-asr-flash", forKey: "byok.asr.provider")

        let config = ASRTranscriptionClientFactory.qwenRunTaskConfig(
            defaults: defaults,
            keyReader: { $0 == "byok.qwen-asr-flash" ? " settings-qwen-key " : nil })

        XCTAssertEqual(config.endpoint.url.absoluteString,
                       "wss://dashscope.aliyuncs.com/api-ws/v1/inference")
        XCTAssertFalse(config.endpoint.usesDedicatedHost)
        XCTAssertEqual(config.apiKey, "settings-qwen-key")
        XCTAssertEqual(config.model, "qwen-audio-3.0-asr-flash-streaming")
    }

    @MainActor
    func testQwenSettingsSurviveQuickProviderReselectionInNextCapture() {
        defaults.set(QwenASRFlashRouting.providerId, forKey: "byok.asr.provider")
        let credentials = ASRCredentialStore()
        let machine = ProviderConfigMachine(
            capability: .asr,
            preferredProviderId: QwenASRFlashRouting.providerId,
            defaults: defaults,
            keyReader: { credentials.read($0) },
            keyWriter: { credentials.write($0, account: $1) })
        machine.load()
        machine.regionRaw = ProviderRegion.singapore.rawValue
        machine.workspaceID = "ws-abc123"
        machine.model = QwenASRFlashRouting.funASRRealtimeModel
        machine.apiKey = "settings-qwen-key"
        machine.writeApiKey()
        machine.refreshBaseURLForSelection()
        machine.persist()

        ModelRouteSelectionActions.applyASRSelection(
            ASREngine.cloudOpenAI.rawValue,
            defaults: defaults)
        ModelRouteSelectionActions.applyASRSelection(
            ASREngine.cloudQwenASRFlashRealtime.rawValue,
            defaults: defaults)
        XCTAssertEqual(
            SettingsASRModelState.effectiveModel(
                providerId: QwenASRFlashRouting.providerId,
                defaults: defaults),
            QwenASRFlashRouting.funASRRealtimeModel)
        XCTAssertFalse(
            SettingsASRModelState.supportsMixedLanguageHints(
                providerId: QwenASRFlashRouting.providerId,
                defaults: defaults))

        credentials.resetReads()
        let config = ASRTranscriptionClientFactory.qwenRunTaskConfig(
            defaults: defaults,
            keyReader: { credentials.read($0) })

        XCTAssertEqual(
            config.endpoint.url.absoluteString,
            "wss://ws-abc123.ap-southeast-1.maas.aliyuncs.com/api-ws/v1/inference")
        XCTAssertEqual(config.model, "fun-asr-realtime")
        XCTAssertEqual(config.apiKey, "settings-qwen-key")
        XCTAssertEqual(
            credentials.recordedReads,
            [CapabilityCredentialAccount.apiKeyAccount(
                providerId: QwenASRFlashRouting.providerId,
                capability: .asr,
                plan: .payg)])
    }

    @MainActor
    func testQwenSettingsAndNextCaptureShareNormalizedEffectiveState() {
        defaults.set(QwenASRFlashRouting.providerId, forKey: "byok.asr.provider")
        defaults.set(
            ProviderRegion.unitedStates.rawValue,
            forKey: "byok.asr.qwen-asr-flash.region")
        defaults.set(
            "ws-abc123.evil.example",
            forKey: "byok.asr.qwen-asr-flash.workspaceId")
        defaults.set(
            "wss://dashscope.aliyuncs.com/api-ws/v1/realtime",
            forKey: "byok.asr.qwen-asr-flash.baseURL")
        defaults.set(
            "qwen3-asr-flash-realtime-2026-02-10",
            forKey: "byok.asr.qwen-asr-flash.model")
        let machine = ProviderConfigMachine(
            capability: .asr,
            preferredProviderId: QwenASRFlashRouting.providerId,
            defaults: defaults,
            keyReader: { _ in "settings-qwen-key" })

        machine.load()
        let config = ASRTranscriptionClientFactory.qwenRunTaskConfig(
            defaults: defaults,
            keyReader: { _ in "settings-qwen-key" })

        let expected = [
            ProviderRegion.china.rawValue,
            "",
            "wss://dashscope.aliyuncs.com/api-ws/v1/inference",
            "qwen-audio-3.0-asr-flash-streaming",
        ]
        XCTAssertEqual(
            [machine.regionRaw, machine.workspaceID, machine.baseURL, machine.model],
            expected)
        XCTAssertEqual(
            [
                config.endpoint.region.rawValue,
                config.endpoint.workspaceID ?? "",
                config.endpoint.url.absoluteString,
                config.model,
            ],
            expected)
    }

    @MainActor
    func testQwenVocabularySettingReachesEachNextCaptureWithoutRestart() {
        defaults.set(QwenASRFlashRouting.providerId, forKey: "byok.asr.provider")
        XCTAssertTrue(ContextHotwordSettings.addManual("Westlaw", defaults: defaults))
        let machine = ProviderConfigMachine(
            capability: .asr,
            preferredProviderId: QwenASRFlashRouting.providerId,
            defaults: defaults,
            keyReader: { _ in "settings-qwen-key" })
        machine.load()
        machine.workspaceID = "ws-first"
        machine.refreshBaseURLForSelection()
        machine.persist()
        machine.precompiledVocabularyID = "vocab-curated-a1b2c3"
        machine.writeQwenPrecompiledVocabulary()

        let synchronized = ASRTranscriptionClientFactory.qwenRunTaskConfig(
            defaults: defaults,
            keyReader: { _ in "settings-qwen-key" })

        machine.workspaceID = "ws-second"
        machine.refreshBaseURLForSelection()
        machine.persist()
        let changed = ASRTranscriptionClientFactory.qwenRunTaskConfig(
            defaults: defaults,
            keyReader: { _ in "settings-qwen-key" })

        XCTAssertEqual(synchronized.precompiledVocabularyID, "vocab-curated-a1b2c3")
        XCTAssertTrue(synchronized.hotwords.isEmpty)
        XCTAssertNil(changed.precompiledVocabularyID)
        XCTAssertEqual(changed.hotwords, ["Westlaw"])
        XCTAssertEqual(
            changed.endpoint.url.absoluteString,
            "wss://ws-second.cn-beijing.maas.aliyuncs.com/api-ws/v1/inference")
    }

    func testQwenRunTaskFallsBackToFullInstantVocabularyAfterLearningMixedTerm() {
        defaults.set("qwen-asr-flash", forKey: "byok.asr.provider")
        XCTAssertTrue(ContextHotwordSettings.addManual("Westlaw", defaults: defaults))
        QwenPrecompiledVocabularySettings.save(
            identifier: "vocab-curated-a1b2c3",
            model: QwenRunTaskEndpoint.defaultModel,
            endpoint: QwenRunTaskEndpoint(region: .china),
            vocabularyTerms: ContextHotwordSettings.qwenPersistentHotwords(defaults: defaults),
            defaults: defaults)
        XCTAssertTrue(ContextHotwordSettings.addAuto("法研 Metis", defaults: defaults))

        let config = ASRTranscriptionClientFactory.qwenRunTaskConfig(
            defaults: defaults, keyReader: { _ in "k" })

        XCTAssertNil(config.precompiledVocabularyID)
        XCTAssertEqual(Set(config.hotwords), ["Westlaw", "法研 Metis"])
    }

    func testQwenRunTaskMalformedBindingFailsOpenWithoutExposingItInConfig() {
        defaults.set("qwen-asr-flash", forKey: "byok.asr.provider")
        defaults.set("Metis", forKey: ContextHotwordSettings.defaultsKey)
        defaults.set("not-json", forKey: QwenPrecompiledVocabularySettings.scopedDefaultsKey)

        let config = ASRTranscriptionClientFactory.qwenRunTaskConfig(
            defaults: defaults, keyReader: { _ in "k" })

        XCTAssertNil(config.precompiledVocabularyID)
        XCTAssertEqual(config.hotwords, ["Metis"])
    }

    func testQwenRunTaskSingaporeWorkspaceOmitsAllUnsupportedVocabulary() {
        defaults.set("qwen-asr-flash", forKey: "byok.asr.provider")
        defaults.set("singapore", forKey: "byok.asr.qwen-asr-flash.region")
        defaults.set("ws-abc123", forKey: "byok.asr.qwen-asr-flash.workspaceId")
        XCTAssertTrue(ContextHotwordSettings.addManual("法研 Metis", defaults: defaults))
        XCTAssertNil(QwenPrecompiledVocabularySettings.save(
            identifier: "vocab-deadbeef",
            model: QwenRunTaskEndpoint.defaultModel,
            endpoint: QwenRunTaskEndpoint(region: .singapore, workspaceID: "ws-abc123"),
            vocabularyTerms: ContextHotwordSettings.qwenPersistentHotwords(defaults: defaults),
            defaults: defaults))

        let config = ASRTranscriptionClientFactory.qwenRunTaskConfig(
            defaults: defaults, keyReader: { _ in "k" })

        XCTAssertFalse(config.endpoint.supportsHotwords)
        XCTAssertNil(config.precompiledVocabularyID)
        XCTAssertTrue(config.hotwords.isEmpty)
    }

    func testQwenRunTaskPreservesHeartbeatAndProviderVADDefaults() {
        defaults.set("qwen-asr-flash", forKey: "byok.asr.provider")

        let config = ASRTranscriptionClientFactory.qwenRunTaskConfig(
            defaults: defaults, keyReader: { _ in "k" })
        XCTAssertTrue(config.heartbeat)
    }

}
