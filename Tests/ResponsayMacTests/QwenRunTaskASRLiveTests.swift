import AVFoundation
import Foundation
import XCTest
@testable import ResponsayCore
@testable import ResponsaySpeech
@testable import ResponsayMac

/// The live acceptance substitutes only the microphone hardware boundary. It decodes the
/// caller-owned Int16 fixture into the same Float32 buffers `AVCaptureAudioRecorder` delivers, then
/// paces them in real time while the shipped Qwen capture service owns PCM encoding and transport.
private final class LivePCMFixtureRecorder: @unchecked Sendable, SpeechAudioRecording {
    private let pcm: Data
    private let lock = NSLock()
    private var feeder: Task<Void, Error>?

    init(pcm: Data) {
        self.pcm = pcm
    }

    func start(
        preferredUID _: String,
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void
    ) throws {
        let pcm = self.pcm
        withLock {
            feeder = Task.detached {
                // 100 ms of 16 kHz mono Int16 audio per frame, paced in real time.
                let frameSize = 3_200
                for start in stride(from: 0, to: pcm.count, by: frameSize) {
                    try Task.checkCancellation()
                    let end = min(start + frameSize, pcm.count)
                    let buffer = Self.floatBuffer(from: pcm.subdata(in: start ..< end))
                    onBuffer(buffer)
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
            }
        }
    }

    func stop() {
        withLock { feeder?.cancel() }
    }

    func waitUntilFinished() async throws {
        try await withLock { feeder }?.value
    }

    private static func floatBuffer(from pcm: Data) -> AVAudioPCMBuffer {
        let sampleCount = pcm.count / MemoryLayout<Int16>.size
        let buffer = AVAudioPCMBuffer(
            pcmFormat: AVCaptureAudioRecorder.deliveredFormat,
            frameCapacity: AVAudioFrameCount(sampleCount))!
        buffer.frameLength = AVAudioFrameCount(sampleCount)
        for index in 0 ..< sampleCount {
            let byteIndex = pcm.index(pcm.startIndex, offsetBy: index * 2)
            let nextByteIndex = pcm.index(after: byteIndex)
            let sampleBits = UInt16(pcm[byteIndex]) | (UInt16(pcm[nextByteIndex]) << 8)
            buffer.floatChannelData![0][index] = Float(Int16(bitPattern: sampleBits)) / 32_767
        }
        return buffer
    }

    private func withLock<Value>(_ body: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

/// Records the effective config that the production router/capture pair sends, then delegates the
/// real exchange to the shipped run-task session. The live test never calls that low-level session.
private final class LiveQwenRunTaskProbe: @unchecked Sendable, QwenRunTaskTranscribing {
    struct ConfigEvidence: Sendable {
        let contextCount: Int
        let contextContainsMetis: Bool
        let hotwordsContainMetis: Bool
    }

    private let lock = NSLock()
    private let session = QwenRunTaskSession(taskResponseTimeoutNanos: 30_000_000_000)
    private var capturedEvidence = [ConfigEvidence]()

    var evidence: [ConfigEvidence] {
        withLock { capturedEvidence }
    }

    func transcribe(
        config: QwenRunTaskCaptureConfig,
        audio: AsyncStream<Data>,
        onFinalSentence: @escaping @Sendable (String) async -> [String],
        onTaskStarted: @escaping @Sendable (QwenRunTaskStartMetric) async -> Void
    ) async throws -> String {
        let evidence = ConfigEvidence(
            contextCount: config.context.count,
            contextContainsMetis: config.context.contains {
                $0.localizedCaseInsensitiveContains("Metis")
            },
            hotwordsContainMetis: config.hotwords.contains("Metis"))
        withLock { capturedEvidence.append(evidence) }
        return try await session.transcribe(
            config: config,
            audio: audio,
            onFinalSentence: onFinalSentence,
            onTaskStarted: onTaskStarted)
    }

    func shutdown() async {
        await session.shutdown()
    }

    private func withLock<Value>(_ body: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

/// Opt-in real-service acceptance for the Qwen streaming ASR path shipped by the app.
///
/// The test consumes a caller-supplied 16 kHz mono Int16 PCM fixture and the existing ASR
/// Keychain credential. Normal local and CI runs skip it, and neither the key nor transcript is
/// logged. It intentionally exercises the production router, capture service, Context history, and
/// run-task session in two bounded tasks: an unassisted baseline, followed by the exact same audio
/// after a real `matis` → `Metis` correction. The enhanced request covers instant vocabulary,
/// mixed-language hints, Context, heartbeat, and session-managed Context refresh.
/// VAD/noise tuning stays on provider defaults; the separate
/// `scripts/qwen-asr-vad-eval.py` live matrix owns any future evidence for changing them.
@MainActor
final class QwenRunTaskASRLiveTests: XCTestCase {
    func testEnhancedStreamingRecognitionAgainstConfiguredAccount() async throws {
        let environment = ProcessInfo.processInfo.environment
        let liveDefaultsName = "com.semanticcraft.responsay.qwen-asr-live-test"
        let liveDefaults = try XCTUnwrap(UserDefaults(suiteName: liveDefaultsName))
        guard environment["RESPONSAY_QWEN_ASR_LIVE"] == "1" || liveDefaults.bool(forKey: "enabled") else {
            throw XCTSkip("Set RESPONSAY_QWEN_ASR_LIVE=1 to run Qwen ASR live acceptance.")
        }
        defer { liveDefaults.removePersistentDomain(forName: liveDefaultsName) }
        let pcmPath = try XCTUnwrap(
            environment["QWEN_ASR_PCM_PATH"] ?? liveDefaults.string(forKey: "pcmPath"))
        let pcm = try Data(contentsOf: URL(fileURLWithPath: pcmPath))
        XCTAssertFalse(pcm.isEmpty)

        let apiKey = try XCTUnwrap(BYOKKeychain.read("byok.qwen-asr-flash"))
        let contextDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let contextFile = contextDirectory.appendingPathComponent("qwen-asr-context-v1.json")
        defer { try? FileManager.default.removeItem(at: contextDirectory) }
        XCTAssertTrue(PersistentASRContextSettings.setEnabled(
            false,
            defaults: liveDefaults,
            fileURL: contextFile))
        ModelRouteSelectionActions.applyASRSelection(
            ASREngine.cloudQwenASRFlashRealtime.rawValue,
            defaults: liveDefaults)
        liveDefaults.set(QwenASRFlashRouting.providerId, forKey: "byok.asr.provider")
        liveDefaults.set(
            ProviderRegion.china.rawValue,
            forKey: "byok.asr.qwen-asr-flash.region")
        liveDefaults.set(
            QwenRunTaskEndpoint.defaultModel,
            forKey: "byok.asr.qwen-asr-flash.model")
        XCTAssertTrue(ContextHotwordSettings.addManual("Responsay", defaults: liveDefaults))
        let scope = "com.semanticcraft.responsay.live-acceptance"
        let contextStore = RecentASRContextSessionStore(
            defaults: liveDefaults,
            fileURL: contextFile)
        let runTask = LiveQwenRunTaskProbe()
        do {
            let baseline = try await transcribe(
                pcm,
                apiKey: apiKey,
                defaults: liveDefaults,
                contextStore: contextStore,
                scope: scope,
                runTask: runTask)
            XCTAssertEqual(runTask.evidence.first?.contextCount, 0)

            XCTAssertEqual(
                CaptureCorrectionLearner.learn(
                    wrong: "matis",
                    correct: "Metis",
                    defaults: liveDefaults,
                    notify: { _ in }),
                .learned)
            let enhancedContext = contextStore.context(for: scope)
            XCTAssertFalse(enhancedContext.isEmpty)
            XCTAssertTrue(enhancedContext.contains {
                $0.localizedCaseInsensitiveContains("Metis")
            })

            let enhanced = try await transcribe(
                pcm,
                apiKey: apiKey,
                defaults: liveDefaults,
                contextStore: contextStore,
                scope: scope,
                runTask: runTask)
            XCTAssertEqual(runTask.evidence.count, 2)
            XCTAssertEqual(runTask.evidence.last?.contextCount, enhancedContext.count)
            XCTAssertTrue(
                runTask.evidence.last?.contextContainsMetis == true,
                "Enhanced request did not include the learned Context alias.")
            XCTAssertTrue(
                runTask.evidence.last?.hotwordsContainMetis == true,
                "Enhanced request did not include the learned hotword.")
            XCTAssertFalse(baseline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(
                baseline.localizedCaseInsensitiveContains("Metis"),
                "The live fixture is not discriminating because the unassisted baseline already contains Metis.")
            XCTAssertTrue(
                enhanced.localizedCaseInsensitiveContains("Metis"),
                "Enhanced decoding did not preserve the learned canonical hotword.")
        } catch {
            await runTask.shutdown()
            throw error
        }
        await runTask.shutdown()
    }

    private func transcribe(
        _ pcm: Data,
        apiKey: String,
        defaults: UserDefaults,
        contextStore: RecentASRContextSessionStore,
        scope: String,
        runTask: LiveQwenRunTaskProbe
    ) async throws -> String {
        let recorder = LivePCMFixtureRecorder(pcm: pcm)
        let router = RoutedSpeechCaptureService(
            contextScopeProvider: { scope },
            defaults: defaults,
            keyReader: { account in
                account == CapabilityCredentialAccount.apiKeyAccount(
                    providerId: QwenASRFlashRouting.providerId,
                    capability: .asr,
                    plan: .payg)
                    ? apiKey
                    : nil
            },
            qwenRunTask: runTask,
            qwenAudioRecorder: { recorder },
            qwenContextStore: contextStore,
            requireQwenMicPermission: {})
        try router.start(locale: .mixed)
        try await recorder.waitUntilFinished()
        return try await router.stop()
    }
}
