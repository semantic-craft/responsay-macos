import AVFoundation
import ResponsayCore
@testable import ResponsaySpeech
import XCTest
@testable import ResponsayMac

private final class ASRRuntimeStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responseData = Data()
    nonisolated(unsafe) static var requestURL: URL?
    nonisolated(unsafe) static var requestHeaders: [String: String] = [:]
    nonisolated(unsafe) static var requestBody = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requestURL = request.url
        Self.requestHeaders = request.allHTTPHeaderFields ?? [:]
        Self.requestBody = request.httpBody ?? Self.readBodyStream(request.httpBodyStream)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ASRRuntimeStubURLProtocol.self]
        return URLSession(configuration: config)
    }

    static func reset(responseData: Data) {
        Self.responseData = responseData
        requestURL = nil
        requestHeaders = [:]
        requestBody = Data()
    }

    private static func readBodyStream(_ stream: InputStream?) -> Data {
        guard let stream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

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

    func testQwenASRFlashUsesFinalOnlyTranscriptionWhileMiMoCanPublishPreview() {
        XCTAssertFalse(
            CloudQwenSpeechCaptureService.usesPostUploadStreamingPreview(
                forProvider: "qwen-asr-flash"))
        XCTAssertTrue(
            CloudQwenSpeechCaptureService.usesPostUploadStreamingPreview(forProvider: "mimo"))
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

    func testSettingsBackedOpenAIClientUsesCapabilityCardSlot() async throws {
        defaults.set("openai", forKey: "byok.asr.provider")
        defaults.set("https://asr.proxy.test/v1", forKey: "byok.asr.openai.baseURL")
        defaults.set("gpt-4o-transcribe", forKey: "byok.asr.openai.model")
        ASRRuntimeStubURLProtocol.reset(responseData: #"{"text":"ok"}"#.data(using: .utf8)!)

        let client = ASRTranscriptionClientFactory.openAI(
            defaults: defaults,
            session: ASRRuntimeStubURLProtocol.session(),
            keyReader: { $0 == "byok.openai" ? "settings-openai-key" : nil })

        let result = try await client.transcribe(
            audio: Data([0x01]),
            mimeType: "audio/wav",
            language: "en")

        XCTAssertEqual(ASRRuntimeStubURLProtocol.requestURL?.absoluteString,
                       "https://asr.proxy.test/v1/audio/transcriptions")
        XCTAssertEqual(ASRRuntimeStubURLProtocol.requestHeaders["Authorization"],
                       "Bearer settings-openai-key")
        XCTAssertEqual(result.model, "gpt-4o-transcribe")
    }

    func testSettingsBackedMimoClientUsesCatalogProviderIdAndSlot() async throws {
        defaults.set("mimo", forKey: "byok.asr.provider")
        defaults.set("https://mimo.proxy.test/v1", forKey: "byok.asr.mimo.baseURL")
        defaults.set("mimo-custom-asr", forKey: "byok.asr.mimo.model")
        ASRRuntimeStubURLProtocol.reset(
            responseData: #"{"choices":[{"message":{"content":"ok"}}]}"#.data(using: .utf8)!)

        let client = ASRTranscriptionClientFactory.mimo(
            defaults: defaults,
            session: ASRRuntimeStubURLProtocol.session(),
            keyReader: { $0 == CapabilityCredentialAccount.apiKeyAccount(
                providerId: "mimo", capability: .asr, plan: .package) ? "settings-mimo-key" : nil })

        let result = try await client.transcribe(
            audio: Data([0x01]),
            mimeType: "audio/wav",
            language: "zh")

        let body = String(decoding: ASRRuntimeStubURLProtocol.requestBody, as: UTF8.self)
        XCTAssertEqual(ASRRuntimeStubURLProtocol.requestURL?.absoluteString,
                       "https://mimo.proxy.test/v1/chat/completions")
        XCTAssertEqual(ASRRuntimeStubURLProtocol.requestHeaders["api-key"],
                       "settings-mimo-key")
        XCTAssertNil(ASRRuntimeStubURLProtocol.requestHeaders["Authorization"])
        XCTAssertTrue(body.contains("mimo-custom-asr"))
        XCTAssertEqual(result.provider, "mimo")
    }

    func testSettingsBackedMimoClientDefaultsToTokenPlanEndpoint() async throws {
        defaults.set("mimo", forKey: "byok.asr.provider")
        ASRRuntimeStubURLProtocol.reset(
            responseData: #"{"choices":[{"message":{"content":"ok"}}]}"#.data(using: .utf8)!)

        let client = ASRTranscriptionClientFactory.mimo(
            defaults: defaults,
            session: ASRRuntimeStubURLProtocol.session(),
            keyReader: { $0 == CapabilityCredentialAccount.apiKeyAccount(
                providerId: "mimo", capability: .asr, plan: .package) ? "settings-mimo-key" : nil })

        _ = try await client.transcribe(
            audio: Data([0x01]),
            mimeType: "audio/wav",
            language: "zh")

        XCTAssertEqual(ASRRuntimeStubURLProtocol.requestURL?.absoluteString,
                       "https://token-plan-cn.xiaomimimo.com/v1/chat/completions")
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
