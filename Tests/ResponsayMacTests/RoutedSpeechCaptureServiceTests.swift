import ResponsayCore
@testable import ResponsaySpeech
import XCTest
@testable import ResponsayMac

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
        let router: SpeechCaptureService = RoutedSpeechCaptureService(
            screenTermHarvester: { $0.beginHarvest(isEnabled: false) })
        XCTAssertNotNil(
            router as? SpeechPartialTranscriptProviding,
            "router must forward partials or the VM-side streaming path is dead for all engines")
    }

    @MainActor
    func testPartialStreamWithoutActiveCaptureFinishesImmediately() async {
        let router = RoutedSpeechCaptureService(
            screenTermHarvester: { $0.beginHarvest(isEnabled: false) })
        var received = [String]()
        // No capture started → the fallback stream must finish at once
        // (a hang here would wedge the VM's partial task).
        for await text in router.partialTranscripts {
            received.append(text)
        }
        XCTAssertTrue(received.isEmpty)
    }

    @MainActor
    func testSecondStartIsRejectedWithoutRestartingTheActiveAdapter() async throws {
        let adapter = DeterministicDictationAdapter(
            result: "first capture",
            level: 0.5,
            partial: nil,
            capability: .init())
        let router = RoutedSpeechCaptureService(
            defaults: defaults,
            isReady: { _ in true },
            adapterForEngine: { _ in adapter })

        try router.start(locale: .english)
        XCTAssertThrowsError(try router.start(locale: .chinese)) { error in
            XCTAssertEqual(error.localizedDescription, "已有语音采集正在进行。")
        }
        XCTAssertEqual(adapter.startedLocale, .english)
        let transcript = try await router.stop()
        XCTAssertEqual(transcript, "first capture")
    }

    @MainActor
    func testEverySelectableLocalSelectionRunsItsAdapterThroughTheRouterInterface() async throws {
        let cases: [(engine: ASREngine, level: Float, partial: String?)] = [
            (.apple, 0.71, "apple partial"),
            (.sensevoiceLocal, 0.72, nil),
            (.qwen3LocalASR, 0.73, nil),
            (.funAsrNanoLocal, 0.74, nil),
        ]
        XCTAssertEqual(
            cases.map(\.engine),
            ASREngine.selectableCases.filter { $0.associatedProviderId == nil })
        XCTAssertTrue(ContextHotwordSettings.addManual("代码仓", defaults: defaults))

        for testCase in cases {
            defaults.set(testCase.engine.rawValue, forKey: ASREngine.defaultsKey)
            let adapter = DeterministicDictationAdapter(
                result: "推到代码厂里",
                level: testCase.level,
                partial: testCase.partial,
                capability: .init())
            var resolved = [ASREngine]()
            let router = RoutedSpeechCaptureService(
                defaults: defaults,
                isReady: { _ in true },
                adapterForEngine: { engine in
                    resolved.append(engine)
                    return adapter
                })

            try router.start(locale: .mixed)
            var levels = [Float]()
            for await level in router.levels { levels.append(level) }
            var partials = [String]()
            for await partial in router.partialTranscripts { partials.append(partial) }
            let final = try await router.stop()

            XCTAssertEqual(resolved, [testCase.engine], testCase.engine.rawValue)
            XCTAssertEqual(adapter.startedLocale, .mixed, testCase.engine.rawValue)
            XCTAssertTrue(adapter.didStop, testCase.engine.rawValue)
            XCTAssertEqual(levels, [testCase.level], testCase.engine.rawValue)
            XCTAssertEqual(partials, testCase.partial.map { [$0] } ?? [], testCase.engine.rawValue)
            XCTAssertEqual(final, "推到代码仓里", testCase.engine.rawValue)
            XCTAssertEqual(
                defaults.string(forKey: ASREngine.defaultsKey),
                testCase.engine.rawValue,
                testCase.engine.rawValue)
        }
    }

    @MainActor
    func testEveryMissingDownloadableModelFailsExplicitlyWithoutSelectingAnotherAdapter() {
        let downloadable = [ASREngine.sensevoiceLocal, .qwen3LocalASR, .funAsrNanoLocal]
        XCTAssertEqual(
            downloadable,
            ASREngine.selectableCases.filter { $0.localModelSpec != nil })

        for engine in downloadable {
            defaults.set(engine.rawValue, forKey: ASREngine.defaultsKey)
            let missingModel = DeterministicDictationAdapter(
                result: "unreachable",
                level: 0,
                partial: nil,
                capability: .init(),
                startError: DeterministicDictationError.missingLocalModel)
            var resolved = [ASREngine]()
            let router = RoutedSpeechCaptureService(
                defaults: defaults,
                isReady: { _ in false },
                adapterForEngine: { selected in
                    resolved.append(selected)
                    return missingModel
                })

            XCTAssertThrowsError(try router.start(locale: .chinese)) { error in
                XCTAssertEqual(error as? DeterministicDictationError, .missingLocalModel)
            }
            XCTAssertEqual(resolved, [engine], engine.rawValue)
            XCTAssertEqual(
                defaults.string(forKey: ASREngine.defaultsKey),
                engine.rawValue,
                engine.rawValue)
        }
    }

    @MainActor
    func testProductionConstructorMapsAppleToItsRouterAdapterBoundary() async throws {
        defaults.set(ASREngine.apple.rawValue, forKey: ASREngine.defaultsKey)
        let apple = DeterministicDictationAdapter(
            result: "apple production mapping",
            level: 0.42,
            partial: "apple partial",
            capability: .init(partialStyle: .realtimeFrameByFrame))
        let qwenBoundary = LocalQwenDictationAdapter()
        let router = makeProductionRouter(
            qwenBoundary: qwenBoundary,
            appleCaptureService: apple,
            localModelInstalled: { $0.isInstalled })

        try router.start(locale: .english)
        let transcript = try await router.stop()

        XCTAssertEqual(apple.startedLocale, .english)
        XCTAssertTrue(apple.didStop)
        XCTAssertEqual(transcript, "apple production mapping")
    }

    @MainActor
    func testProductionConstructorMapsEveryDownloadableLocalToItsOwnMissingModelError() {
        let cases: [(ASREngine, LocalModelSpec)] = [
            (.sensevoiceLocal, .senseVoiceSmall),
            (.qwen3LocalASR, .qwen3ASR),
            (.funAsrNanoLocal, .funAsrNano),
        ]

        for (engine, spec) in cases {
            defaults.set(engine.rawValue, forKey: ASREngine.defaultsKey)
            let qwenBoundary = LocalQwenDictationAdapter()
            let router = makeProductionRouter(
                qwenBoundary: qwenBoundary,
                appleCaptureService: DeterministicDictationAdapter(
                    result: "unreachable Apple",
                    level: 0,
                    partial: nil,
                    capability: .init()),
                localModelInstalled: { _ in false })

            XCTAssertThrowsError(try router.start(locale: .chinese)) { error in
                XCTAssertTrue(
                    error.localizedDescription.contains(spec.displayName),
                    "\(engine.rawValue) produced \(error.localizedDescription)")
            }
            XCTAssertFalse(qwenBoundary.started, engine.rawValue)
        }
    }

    @MainActor
    func testScreenTermHarvestStartsOnlyAfterAdapterStartSucceeds() throws {
        defaults.set(ASREngine.apple.rawValue, forKey: ASREngine.defaultsKey)
        var successfulHarvests = 0
        let successful = DeterministicDictationAdapter(
            result: "ok", level: 0, partial: nil, capability: .init())
        let successfulRouter = RoutedSpeechCaptureService(
            defaults: defaults,
            isReady: { _ in true },
            adapterForEngine: { _ in successful },
            screenTermHarvester: { _ in successfulHarvests += 1 })

        try successfulRouter.start(locale: .mixed)
        XCTAssertEqual(successfulHarvests, 1)

        var failedHarvests = 0
        let failing = DeterministicDictationAdapter(
            result: "unreachable",
            level: 0,
            partial: nil,
            capability: .init(),
            startError: DeterministicDictationError.missingLocalModel)
        let failingRouter = RoutedSpeechCaptureService(
            defaults: defaults,
            isReady: { _ in true },
            adapterForEngine: { _ in failing },
            screenTermHarvester: { _ in failedHarvests += 1 })

        XCTAssertThrowsError(try failingRouter.start(locale: .mixed))
        XCTAssertEqual(failedHarvests, 0)
    }

    @MainActor
    func testQwenFinalizationUsesTheTermsFrozenAtRequestStart() async throws {
        defaults.set(
            ASREngine.cloudQwenASRFlashRealtime.rawValue,
            forKey: ASREngine.defaultsKey)
        let adapter = DeterministicDictationAdapter(
            result: "Later Screen One, Later Screen Two",
            level: 0,
            partial: nil,
            capability: .init(needsEchoFilter: true))
        let router = RoutedSpeechCaptureService(
            defaults: defaults,
            isReady: { _ in true },
            adapterForEngine: { _ in adapter },
            screenTermHarvester: { terms in
                terms.set(["Later Screen One", "Later Screen Two"])
            })

        try router.start(locale: .mixed)
        let final = try await router.stop()

        XCTAssertEqual(final, "Later Screen One, Later Screen Two")
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
                isReady: { _ in true },
                adapterForEngine: { engine in Self.deterministicAdapter(for: engine) })

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
            isReady: { _ in false },
            adapterForEngine: { engine in
                if engine == .apple {
                    return DeterministicDictationAdapter(
                        result: "apple fallback", level: 0.77, partial: nil,
                        capability: .init())
                }
                return Self.deterministicAdapter(for: engine)
            })

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
            isReady: { _ in true },
            adapterForEngine: { _ in
                DeterministicDictationAdapter(
                    result: "推到代码厂里", level: 0.11, partial: "推到代码",
                    capability: .init(partialStyle: .postUploadSSE, needsEchoFilter: true))
            })

        try router.start(locale: .mixed)

        let final = try await router.stop()
        XCTAssertEqual(final, "推到代码仓里")
    }

    @MainActor
    private static func deterministicAdapter(
        for engine: ASREngine
    ) -> DeterministicDictationAdapter {
        switch engine {
        case .cloudOpenAI:
            DeterministicDictationAdapter(
                result: "openai final", level: 0.11, partial: "openai partial",
                capability: .init(partialStyle: .postUploadSSE, needsEchoFilter: true))
        case .cloudMimo:
            DeterministicDictationAdapter(
                result: "mimo final", level: 0.22, partial: "mimo partial",
                capability: .init(partialStyle: .postUploadSSE, needsEchoFilter: true))
        case .cloudGemini:
            DeterministicDictationAdapter(
                result: "gemini final", level: 0.33, partial: "gemini partial",
                capability: .init(partialStyle: .postUploadSSE, needsEchoFilter: true))
        case .cloudQwenASRFlashRealtime:
            DeterministicDictationAdapter(
                result: "qwen final", level: 0.44, partial: nil,
                capability: .init(partialStyle: .none, needsEchoFilter: true))
        case .cloudVolcengineRealtime:
            DeterministicDictationAdapter(
                result: "volcengine final", level: 0.55, partial: nil,
                capability: .init(partialStyle: .none, needsEchoFilter: true))
        case .customOpenAI:
            DeterministicDictationAdapter(
                result: "custom final", level: 0.66, partial: "custom partial",
                capability: .init(partialStyle: .postUploadSSE, needsEchoFilter: true))
        case .apple, .sensevoiceLocal, .qwen3LocalASR, .funAsrNanoLocal:
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

    @MainActor
    private func makeProductionRouter(
        qwenBoundary: LocalQwenDictationAdapter,
        appleCaptureService: any SpeechCaptureService,
        localModelInstalled: @escaping @Sendable (LocalModelSpec) -> Bool
    ) -> RoutedSpeechCaptureService {
        RoutedSpeechCaptureService(
            contextScopeProvider: { nil },
            defaults: defaults,
            keyReader: { _ in "synthetic-unused-key" },
            qwenRunTask: qwenBoundary,
            qwenAudioRecorder: { qwenBoundary },
            qwenContextStore: RecentASRContextSessionStore(
                defaults: defaults,
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("production-map-\(UUID().uuidString).json")),
            requireQwenMicPermission: {},
            appleCaptureService: appleCaptureService,
            localModelInstalled: localModelInstalled)
    }

}
