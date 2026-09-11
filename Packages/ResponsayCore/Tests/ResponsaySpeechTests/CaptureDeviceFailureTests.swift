#if os(macOS)
import AVFoundation
import XCTest
import ResponsayCore
@testable import ResponsaySpeech

/// Never calls AVCaptureSession.startRunning: the fake only emits lifecycle notifications.
private final class SilentSession: AVCaptureSession, @unchecked Sendable {
    private var fakeRunning = false
    override var isRunning: Bool { fakeRunning }
    override func startRunning() { fakeRunning = true }
    override func stopRunning() {
        fakeRunning = false
        NotificationCenter.default.post(name: Self.didStopRunningNotification, object: self)
    }
}

private final class SessionSequence: @unchecked Sendable {
    let old = SilentSession()
    private var first = true
    private let lock = NSLock()
    func next() -> AVCaptureSession {
        lock.lock()
        defer { lock.unlock() }
        if first { first = false; return old }
        return SilentSession()
    }
}

private final class SilentDevice: NSObject, @unchecked Sendable {}

final class CaptureDeviceFailureTests: XCTestCase {
    func testNotificationFailureIsTerminalAndNormalStopDoesNotReportFailure() throws {
        for event in [AVCaptureSession.runtimeErrorNotification,
                      AVCaptureSession.didStopRunningNotification,
                      AVCaptureSession.wasInterruptedNotification,
                      AVCaptureDevice.wasDisconnectedNotification] {
            let session = SilentSession()
            let device = SilentDevice()
            let recorder = AVCaptureAudioRecorder(makeSession: { session }, configure: { _, _, _ in device })
            let failed = expectation(description: event.rawValue)
            failed.assertForOverFulfill = true
            try recorder.start(preferredUID: "", onBuffer: { _ in XCTFail("No hardware") },
                               onFailure: { _ in failed.fulfill() })
            let object: AnyObject = event == AVCaptureDevice.wasDisconnectedNotification ? device : session
            NotificationCenter.default.post(name: event, object: object)
            NotificationCenter.default.post(name: event, object: object)
            // No actor yield: stop must synchronously observe the queued terminal failure.
            XCTAssertThrowsError(try recorder.stop())
            wait(for: [failed], timeout: 2)
            XCTAssertFalse(session.isRunning)
            try recorder.start(preferredUID: "", onBuffer: { _ in }, onFailure: { _ in XCTFail("Normal stop") })
            try recorder.stop()
            try recorder.stop()
        }
    }

    func testOldSessionAndOtherDeviceNotificationsCannotFailNewRecording() throws {
        let device = SilentDevice()
        let sessions = SessionSequence()
        let recorder = AVCaptureAudioRecorder(makeSession: { sessions.next() }, configure: { _, _, _ in device })
        try recorder.start(preferredUID: "", onBuffer: { _ in }, onFailure: { _ in XCTFail("Old capture") })
        try recorder.stop()
        try recorder.start(preferredUID: "", onBuffer: { _ in }, onFailure: { _ in XCTFail("Unrelated notification") })
        NotificationCenter.default.post(name: AVCaptureSession.runtimeErrorNotification, object: sessions.old)
        NotificationCenter.default.post(name: AVCaptureDevice.wasDisconnectedNotification, object: SilentDevice())
        try recorder.stop()
    }

    @MainActor
    func testVolcFailureCancelsTransportFinishesStreamsAndAllowsRestart() async throws {
        let recorder = FailureRecorder()
        let ended = expectation(description: "transport cancelled")
        let service = VolcengineStreamingCaptureService(transcriber: { { audio in
            for await _ in audio {}
            defer { ended.fulfill() }
            try Task.checkCancellation()
            return "must not insert"
        } }, audioRecorder: { recorder }, requireMicPermission: {})
        try service.start(locale: .chinese)
        let failures = service.captureFailures
        let levels = service.levels
        let oldFailure = recorder.failure!
        recorder.fail()
        var messages = [String]()
        for await message in failures { messages.append(message) }
        for await _ in levels { XCTFail("No audio") }
        XCTAssertEqual(messages.count, 1)
        await fulfillment(of: [ended], timeout: 2)
        do { _ = try await service.stop(); XCTFail("Failure must discard text") } catch {}
        try service.start(locale: .chinese)
        oldFailure("stale")
        await Task.yield()
        XCTAssertEqual(recorder.stops, 1)
        await service.cancel()
    }

    @MainActor
    func testBatchAndQwenImmediateFailureCannotReturnTranscript() async throws {
        for isBatch in [true, false] {
            let recorder = FailureRecorder()
            let service: any SpeechCaptureService
            if isBatch {
                service = CloudQwenSpeechCaptureService(provider: "synthetic", requireMicPermission: {},
                    audioRecorder: { recorder }, clientBuilder: { _ in NeverTranscribe() })
            } else {
                service = QwenRunTaskStreamingCaptureService(
                    configProvider: { .init(endpoint: .init(region: .china), apiKey: "synthetic-key") },
                    runTask: WaitForAudio(), audioRecorder: { recorder }, requireMicPermission: {})
            }
            try service.start(locale: .chinese)
            recorder.fail()
            // Deliberately do not give the asynchronous failure callback a MainActor turn.
            do { _ = try await service.stop(); XCTFail("Failed audio must not transcribe or salvage") } catch {}
            try service.start(locale: .chinese)
            await service.cancel()
        }
    }

    @MainActor
    func testTransportEndingWhileListeningStopsRecorder() async throws {
        let recorder = FailureRecorder()
        let service = VolcengineStreamingCaptureService(transcriber: { { _ in
            throw NSError(domain: "synthetic-transport", code: 1)
        } }, audioRecorder: { recorder }, requireMicPermission: {})
        try service.start(locale: .chinese)
        for await _ in service.captureFailures {}
        XCTAssertEqual(recorder.stops, 1)
        do { _ = try await service.stop(); XCTFail("Expected failure") } catch {}
    }
}

private final class FailureRecorder: SpeechAudioRecording {
    var failure: (@Sendable (String) -> Void)?
    var stops = 0
    private var failed = false
    func start(preferredUID: String, onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
               onFailure: @escaping @Sendable (String) -> Void) throws {
        failed = false
        failure = onFailure
    }
    func stop() throws {
        stops += 1
        if failed { throw CoachAPIError.message("synthetic device failure") }
    }
    func fail() { failed = true; failure?("synthetic device failure") }
}
private struct NeverTranscribe: TranscriptionAPI {
    func transcribe(audio: Data, mimeType: String, language: String) async throws -> TranscriptionResult {
        XCTFail("Failed batch recording must never be uploaded")
        throw CancellationError()
    }
}

private struct WaitForAudio: QwenRunTaskTranscribing {
    func transcribe(config: QwenRunTaskCaptureConfig, audio: AsyncStream<Data>,
                    onFinalSentence: @escaping @Sendable (String) async -> [String],
                    onTaskStarted: @escaping @Sendable (QwenRunTaskStartMetric) async -> Void) async throws -> String {
        for await _ in audio {}
        try Task.checkCancellation()
        return "must not insert"
    }
}
#endif
