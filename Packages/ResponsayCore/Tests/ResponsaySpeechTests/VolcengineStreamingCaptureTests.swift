#if os(macOS)
import AVFoundation
import XCTest
@testable import ResponsaySpeech

final class VolcengineStreamingCaptureTests: XCTestCase {
    @MainActor
    func testAudioReachesTranscriberBeforeStopAndStopReturnsWholeFinal() async throws {
        let received = expectation(description: "audio uploaded while recording")
        let recorder = VolcTestRecorder()
        let service = VolcengineStreamingCaptureService(
            transcriber: { { audio in
                var bytes = 0
                for await frame in audio {
                    bytes += frame.count
                    received.fulfill()
                }
                XCTAssertEqual(bytes, 6400)
                return "整句最终结果。"
            } }, audioRecorder: { recorder }, requireMicPermission: {})
        try service.start(locale: .chinese)
        recorder.emit()
        await fulfillment(of: [received], timeout: 2)
        XCTAssertEqual(recorder.stops, 0)
        XCTAssertEqual(service.captureCapability.partialStyle, .none)
        let text = try await service.stop()
        XCTAssertEqual(text, "整句最终结果。")
        XCTAssertEqual(recorder.stops, 1)
    }

    @MainActor
    func testRecorderFailureCleansUpAndAllowsRestart() async throws {
        let recorder = VolcTestRecorder()
        recorder.shouldFail = true
        let service = VolcengineStreamingCaptureService(
            transcriber: { { audio in
                for await _ in audio {}
                try Task.checkCancellation()
                return "final"
            } }, audioRecorder: { recorder }, requireMicPermission: {})
        XCTAssertThrowsError(try service.start(locale: .chinese))
        XCTAssertEqual(recorder.stops, 1)
        recorder.shouldFail = false
        try service.start(locale: .chinese)
        let text = try await service.stop()
        XCTAssertEqual(text, "final")
        XCTAssertEqual(recorder.stops, 2)
    }

    @MainActor
    func testStopCancellationCancelsTranscription() async throws {
        let waiting = expectation(description: "waiting for final")
        let cancelled = expectation(description: "transcription cancelled")
        let service = VolcengineStreamingCaptureService(
            transcriber: { { audio in
                for await _ in audio {}
                waiting.fulfill()
                do { try await Task.sleep(for: .seconds(60)) }
                catch { cancelled.fulfill(); throw error }
                return "unexpected"
            } }, audioRecorder: { VolcTestRecorder() }, requireMicPermission: {})
        try service.start(locale: .chinese)
        let stop = Task { try await service.stop() }
        await fulfillment(of: [waiting], timeout: 2)
        stop.cancel()
        do { _ = try await stop.value; XCTFail("Expected cancellation") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        await fulfillment(of: [cancelled], timeout: 2)
    }
}

private final class VolcTestRecorder: SpeechAudioRecording {
    private var callback: (@Sendable (AVAudioPCMBuffer) -> Void)?
    var stops = 0
    var shouldFail = false
    func start(preferredUID: String, onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
        onFailure: @escaping @Sendable (String) -> Void) throws {
        if shouldFail { throw NSError(domain: "TestRecorder", code: 1) }
        callback = onBuffer
    }
    func stop() { stops += 1; callback = nil }
    func emit() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 3200)!
        buffer.frameLength = 3200
        buffer.floatChannelData![0].initialize(repeating: 0.2, count: 3200)
        callback?(buffer)
    }
}
#endif
