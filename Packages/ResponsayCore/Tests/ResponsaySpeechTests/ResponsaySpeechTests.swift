import AVFoundation
import ResponsayCore
import XCTest
@testable import ResponsaySpeech

final class ResponsaySpeechTests: XCTestCase {
    func testModuleLoads() {
        XCTAssertTrue(true)
    }

    #if os(macOS)
    /// `stop()`'s final wait must scale with the recording (a reconnect replay of a long capture
    /// needs the extra time), stay above the session's own 90 s final wait so salvage applies
    /// first, and clamp at 120 s so the input method can never wedge.
    func testStopWaitScalesWithRecordingAndIsCapped() {
        XCTAssertEqual(
            QwenRunTaskStreamingCaptureService.stopWaitNanos(audioBytes: 0),
            12_000_000_000)
        // 60 s of 16 kHz mono Int16 audio = 1,920,000 bytes → +30 s of grace.
        XCTAssertEqual(
            QwenRunTaskStreamingCaptureService.stopWaitNanos(audioBytes: 1_920_000),
            42_000_000_000)
        XCTAssertEqual(
            QwenRunTaskStreamingCaptureService.stopWaitNanos(audioBytes: 28_800_000),
            120_000_000_000)
    }

    /// When the session fails even after its own retries, `stop()` must return the final
    /// sentences already recognised instead of dropping the whole recording — a long dictation
    /// degrades to "missing the tail", never to nothing.
    @MainActor
    func testStopSalvagesRecognisedSentencesWhenTheSessionFails() async throws {
        let service = QwenRunTaskStreamingCaptureService(
            configProvider: { Self.config() },
            runTask: ScriptedRunTask(finals: ["停顿前的内容。", "停顿后的内容。"],
                                     error: QwenRunTaskSessionError.taskFailed("boom")),
            audioRecorder: { NoopSpeechRecorder() },
            requireMicPermission: {})

        try service.start(locale: .chinese)
        let text = try await service.stop()

        XCTAssertEqual(text, "停顿前的内容。停顿后的内容。")
    }

    /// With nothing recognised, the failure must surface as an error (the capture flow shows its
    /// message) — never a silent empty transcript.
    @MainActor
    func testStopThrowsWhenTheSessionFailsBeforeAnySentence() async {
        let service = QwenRunTaskStreamingCaptureService(
            configProvider: { Self.config() },
            runTask: ScriptedRunTask(finals: [],
                                     error: QwenRunTaskSessionError.taskFailed("boom")),
            audioRecorder: { NoopSpeechRecorder() },
            requireMicPermission: {})

        do {
            try service.start(locale: .chinese)
            _ = try await service.stop()
            XCTFail("Expected the session failure to surface from stop().")
        } catch QwenRunTaskSessionError.taskFailed(let message) {
            XCTAssertEqual(message, "boom")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private static func config() -> QwenRunTaskCaptureConfig {
        QwenRunTaskCaptureConfig(endpoint: .init(region: .china), apiKey: "synthetic-test-key")
    }
    #endif
}

#if os(macOS)
/// Session double: forwards the scripted finals through the capture's callback (populating the
/// salvage tally exactly like live per-sentence results do), then fails or returns.
private struct ScriptedRunTask: QwenRunTaskTranscribing {
    var finals: [String]
    var error: Error?

    func transcribe(
        config: QwenRunTaskCaptureConfig,
        audio: AsyncStream<Data>,
        onFinalSentence: @escaping @Sendable (String) async -> [String],
        onTaskStarted: @escaping @Sendable (QwenRunTaskStartMetric) async -> Void
    ) async throws -> String {
        for text in finals {
            _ = await onFinalSentence(text)
        }
        if let error { throw error }
        return TranscriptJoiner.mergeSegments(finals)
    }
}

private final class NoopSpeechRecorder: SpeechAudioRecording {
    func start(
        preferredUID: String,
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void
    ) throws {}

    func stop() {}
}
#endif
