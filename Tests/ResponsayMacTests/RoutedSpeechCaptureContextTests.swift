import AVFoundation
import ResponsayCore
@testable import ResponsaySpeech
import XCTest
@testable import ResponsayMac

/// Deterministic adapter for the only two external Qwen capture boundaries. The production router,
/// streaming capture service, and Context store remain real.
private final class LocalQwenContextCaptureAdapter: @unchecked Sendable,
    SpeechAudioRecording, QwenRunTaskTranscribing
{
    private let lock = NSLock()
    private let finalSentences: [String]
    private var _config: QwenRunTaskCaptureConfig?
    private var _callbackContext = [String]()

    init(finalSentences: [String]) {
        self.finalSentences = finalSentences
    }

    var config: QwenRunTaskCaptureConfig? { withLock { _config } }
    var callbackContext: [String] { withLock { _callbackContext } }

    func start(
        preferredUID _: String,
        onBuffer _: @escaping @Sendable (AVAudioPCMBuffer) -> Void
    ) throws {}

    func stop() {}

    func transcribe(
        config: QwenRunTaskCaptureConfig,
        audio: AsyncStream<Data>,
        onFinalSentence: @escaping @Sendable (String) async -> [String],
        onTaskStarted: @escaping @Sendable (QwenRunTaskStartMetric) async -> Void
    ) async throws -> String {
        withLock { _config = config }
        await onTaskStarted(.init(reusedConnection: false, runTaskToStartedNanos: 1_000_000))
        for await _ in audio {}
        for finalSentence in finalSentences {
            let context = await onFinalSentence(finalSentence)
            withLock { _callbackContext = context }
        }
        return "context capture complete"
    }

    private func withLock<Value>(_ body: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

@MainActor
final class RoutedSpeechCaptureContextTests: XCTestCase {
    private var defaults: UserDefaults!
    private var contextDirectoryURL: URL!
    private var contextFileURL: URL!
    private var now: Date!
    private let suite = "routed-asr-context-tests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
        contextDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        contextFileURL = contextDirectoryURL.appendingPathComponent("qwen-asr-context-v1.json")
        now = Date(timeIntervalSince1970: 2_000_000_000)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: contextDirectoryURL)
        defaults = nil
        contextDirectoryURL = nil
        contextFileURL = nil
        now = nil
        super.tearDown()
    }

    func testQwenProductionContextStaysInCurrentSessionAndTargetAppWhenPersistenceIsOff() async throws {
        let sessionStore = makeContextStore()
        let notesCapture = LocalQwenContextCaptureAdapter(
            finalSentences: ["Notes session final"])

        try await capture(
            adapter: notesCapture,
            scope: "com.apple.Notes",
            contextStore: sessionStore)

        XCTAssertEqual(notesCapture.config?.context, [])
        XCTAssertEqual(notesCapture.callbackContext, ["Notes session final"])

        let sameSession = LocalQwenContextCaptureAdapter(finalSentences: [])
        try await capture(
            adapter: sameSession,
            scope: "com.apple.Notes",
            contextStore: sessionStore)
        XCTAssertEqual(sameSession.config?.context, ["Notes session final"])

        let otherApp = LocalQwenContextCaptureAdapter(finalSentences: [])
        try await capture(
            adapter: otherApp,
            scope: "com.apple.mail",
            contextStore: sessionStore)
        XCTAssertEqual(otherApp.config?.context, [])

        let restarted = LocalQwenContextCaptureAdapter(finalSentences: [])
        try await capture(
            adapter: restarted,
            scope: "com.apple.Notes",
            contextStore: makeContextStore())
        XCTAssertEqual(restarted.config?.context, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: contextFileURL.path))
    }

    func testQwenProductionContextRecoversLengthBoundedAliasesOnlyForTargetApp() async throws {
        XCTAssertTrue(PersistentASRContextSettings.setEnabled(
            true,
            defaults: defaults,
            fileURL: contextFileURL))
        XCTAssertEqual(
            CaptureCorrectionLearner.learn(
                wrong: "matis",
                correct: "Metis",
                defaults: defaults,
                notify: { _ in }),
            .learned)
        let longRawFinal = "matis " + String(repeating: "x", count: 500)
        let sessionStore = makeContextStore()

        try await capture(
            adapter: LocalQwenContextCaptureAdapter(finalSentences: [longRawFinal]),
            scope: "com.apple.Notes",
            contextStore: sessionStore)
        now = now.addingTimeInterval(1)
        try await capture(
            adapter: LocalQwenContextCaptureAdapter(finalSentences: ["Mail raw final"]),
            scope: "com.apple.mail",
            contextStore: sessionStore)

        let restartedStore = makeContextStore()
        let recoveredNotes = LocalQwenContextCaptureAdapter(finalSentences: [])
        try await capture(
            adapter: recoveredNotes,
            scope: "com.apple.Notes",
            contextStore: restartedStore)
        let expectedNotes = HotwordHardMatch.enforce(
            String(longRawFinal.prefix(PersistentASRContextStore.maximumCharactersPerItem)),
            userTerms: [],
            seedTerms: [],
            learnedAliases: ["matis": "Metis"]).text
        XCTAssertEqual(recoveredNotes.config?.context, [expectedNotes])
        XCTAssertEqual(recoveredNotes.config?.context.first?.count, 400)

        let recoveredMail = LocalQwenContextCaptureAdapter(finalSentences: [])
        try await capture(
            adapter: recoveredMail,
            scope: "com.apple.mail",
            contextStore: restartedStore)
        XCTAssertEqual(recoveredMail.config?.context, ["Mail raw final"])

        let unrelatedApp = LocalQwenContextCaptureAdapter(finalSentences: [])
        try await capture(
            adapter: unrelatedApp,
            scope: "com.apple.TextEdit",
            contextStore: restartedStore)
        XCTAssertEqual(unrelatedApp.config?.context, [])
    }

    func testQwenProductionContextEnforcesCountAndTTLAfterRestart() async throws {
        XCTAssertTrue(PersistentASRContextSettings.setEnabled(
            true,
            defaults: defaults,
            fileURL: contextFileURL))
        let sessionStore = makeContextStore()
        let anchor = now!
        for index in 1...6 {
            now = anchor.addingTimeInterval(TimeInterval(index))
            try await capture(
                adapter: LocalQwenContextCaptureAdapter(
                    finalSentences: ["raw final \(index)"]),
                scope: "com.apple.Notes",
                contextStore: sessionStore)
        }

        let recovered = LocalQwenContextCaptureAdapter(finalSentences: [])
        try await capture(
            adapter: recovered,
            scope: "com.apple.Notes",
            contextStore: makeContextStore())
        XCTAssertEqual(recovered.config?.context, (2...6).map { "raw final \($0)" })

        now = anchor.addingTimeInterval(6 + PersistentASRContextStore.timeToLive)
        let expired = LocalQwenContextCaptureAdapter(finalSentences: [])
        try await capture(
            adapter: expired,
            scope: "com.apple.Notes",
            contextStore: makeContextStore())
        XCTAssertEqual(expired.config?.context, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: contextFileURL.path))
    }

    func testQwenProductionContextFailsClosedWhenExpiredStorageCannotBeRemoved() async throws {
        XCTAssertTrue(PersistentASRContextSettings.setEnabled(
            true,
            defaults: defaults,
            fileURL: contextFileURL))
        let anchor = now!
        try await capture(
            adapter: LocalQwenContextCaptureAdapter(
                finalSentences: ["private raw final"]),
            scope: "com.apple.Notes",
            contextStore: makeContextStore())
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: contextFileURL.path)
        defer {
            try? FileManager.default.setAttributes(
                [.immutable: false],
                ofItemAtPath: contextFileURL.path)
        }
        now = anchor.addingTimeInterval(PersistentASRContextStore.timeToLive)

        let captureAfterFailure = LocalQwenContextCaptureAdapter(finalSentences: [])
        try await capture(
            adapter: captureAfterFailure,
            scope: "com.apple.Notes",
            contextStore: makeContextStore())

        XCTAssertEqual(captureAfterFailure.config?.context, [])
        XCTAssertFalse(PersistentASRContextSettings.isEnabled(defaults: defaults))
        XCTAssertTrue(FileManager.default.fileExists(atPath: contextFileURL.path))
    }

    private func makeContextStore() -> RecentASRContextSessionStore {
        RecentASRContextSessionStore(
            defaults: defaults,
            fileURL: contextFileURL,
            now: { self.now },
            expiryScheduler: { _, _ in {} })
    }

    private func capture(
        adapter: LocalQwenContextCaptureAdapter,
        scope: String,
        contextStore: RecentASRContextSessionStore
    ) async throws {
        ModelRouteSelectionActions.applyASRSelection(
            ASREngine.cloudQwenASRFlashRealtime.rawValue,
            defaults: defaults)
        let router = RoutedSpeechCaptureService(
            contextScopeProvider: { scope },
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
        _ = try await router.stop()
    }
}
