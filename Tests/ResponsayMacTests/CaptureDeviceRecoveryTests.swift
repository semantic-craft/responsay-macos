import AVFoundation
import ResponsayCore
import ResponsaySpeech
import XCTest
@testable import ResponsayMac

@MainActor
final class CaptureDeviceRecoveryTests: XCTestCase {
    func testOfflineFailureReleasesCaptureAndRouterCanRestart() async throws {
        let recorder = DisconnectedRecorder()
        let service = OfflineSherpaCaptureService(
            spec: .senseVoiceSmall, audioRecorder: { recorder },
            isModelInstalled: { true }, makeRecognizer: { UnusedRecognizer() })
        let suite = "CaptureDeviceRecoveryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let router = RoutedSpeechCaptureService(defaults: defaults, isReady: { _ in true },
                                                adapterForEngine: { _ in service })
        try router.start(locale: .chinese)
        recorder.failure?("synthetic disconnect")
        var messages = [String]()
        for await message in router.captureFailures { messages.append(message) }
        XCTAssertEqual(messages, ["synthetic disconnect"])
        XCTAssertFalse(service.isCapturing)
        XCTAssertEqual(recorder.stops, 1)
        do { _ = try await router.stop(); XCTFail("Do not recognize failed audio") } catch {}
        try router.start(locale: .chinese)
        XCTAssertTrue(service.isCapturing)
        await router.cancel()
        XCTAssertFalse(service.isCapturing)
    }
}

private final class DisconnectedRecorder: SpeechAudioRecording {
    var failure: (@Sendable (String) -> Void)?
    var stops = 0
    func start(preferredUID: String, onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
               onFailure: @escaping @Sendable (String) -> Void) throws { failure = onFailure }
    func stop() { stops += 1 }
}

private final class UnusedRecognizer: OfflineSherpaRecognizer {
    func transcribeText(_ samples: [Float], sampleRate: Int) throws -> String {
        XCTFail("Failed audio must not be recognized")
        return ""
    }
}
