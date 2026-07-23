import AVFoundation
import XCTest
@testable import ResponsayMac

final class FireRedASR2AEDTests: XCTestCase {
    private let spec = LocalModelSpec.fireRedASR2AED

    func testFireRedASR2AEDIsRetiredFromUserFacingLists() {
        // Retired 2026-06-17 (no clear advantage over SenseVoice): no longer offered in the
        // picker or the offline-models download list. The spec/recognizer stay defined for
        // raw-value compat + migration (see `testStoredFireRedASR2ValueMigratesToSenseVoice`).
        XCTAssertFalse(ASREngine.selectableCases.contains(.fireRedASR2AEDLocal))
        XCTAssertFalse(LocalModelRegistry.downloadable.map(\.id).contains(ASREngine.fireRedASR2AEDLocal.rawValue))
        // Spec + recognizer support remain so already-installed copies don't crash.
        XCTAssertEqual(spec.family, .fireRedAsrAed)
        XCTAssertEqual(spec.capability, .asr)
        XCTAssertTrue(LocalModelSelfCheck.supports(.fireRedAsrAed))
    }

    func testStoredFireRedASR2ValueMigratesToSenseVoice() {
        // Retired 2026-06-17: a stored FireRedASR2 selection migrates to the comparable offline AED.
        let defaults = UserDefaults(suiteName: "test.firered.retire")!
        defaults.set(ASREngine.fireRedASR2AEDLocal.rawValue, forKey: ASREngine.defaultsKey)
        XCTAssertEqual(ASREngine.selected(defaults: defaults), .sensevoiceLocal)
    }

    /// Real transcription against the installed FireRedASR2 AED model (skips if absent).
    func testTranscribesSample() throws {
        try XCTSkipUnless(spec.isInstalled, "FireRedASR2 AED not installed; skipping")
        let recognizer = try FireRedASR2AEDRecognizer(modelDir: spec.storagePath)

        let wav = spec.storagePath.appendingPathComponent("test_wavs/0.wav")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: wav.path), "sample missing")
        let file = try AVAudioFile(forReading: wav)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let channel = try XCTUnwrap(buffer.floatChannelData)
        let samples = Array(UnsafeBufferPointer(start: channel[0], count: Int(buffer.frameLength)))

        let text = try recognizer.transcribeText(samples, sampleRate: 16_000)
        print("FireRedASR2 AED 0.wav → \(text)")
        XCTAssertFalse(text.isEmpty, "FireRedASR2 AED produced no transcript")
    }

    /// Self-check works for the FireRedASR2 AED family too (rtfX vs expected).
    func testSelfCheck() throws {
        try XCTSkipUnless(spec.isInstalled, "FireRedASR2 AED not installed; skipping")
        let report = try LocalModelSelfCheck.runASR(spec)
        print("FireRedASR2 AED self-check → \(report.summary)")
        XCTAssertFalse(report.transcript.isEmpty)
        XCTAssertGreaterThan(report.realtimeFactor, 0)
    }

    /// Real download + checksum + extraction + transcription smoke. Off by default
    /// because the official archive is ~839 MB; run with RUN_NETWORK_TESTS=1.
    func testNetworkDownloadAndSelfCheck() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_NETWORK_TESTS"] == "1",
            "FireRedASR2 AED network smoke disabled (set RUN_NETWORK_TESTS=1 to run)")

        if !spec.isInstalled {
            try await LocalModelDownloader.install(spec) { _ in }
        }
        let report = try LocalModelSelfCheck.runASR(spec)
        print("FireRedASR2 AED network self-check → \(report.summary) transcript=\(report.transcript)")
        XCTAssertFalse(report.transcript.isEmpty)
        XCTAssertGreaterThan(report.realtimeFactor, 0)
    }
}
