import XCTest
@testable import ResponsayMac
import ResponsayCore

/// 202 — on-device Kokoro synth. T1 (file-presence behavior, no model) runs in CI;
/// the synth + self-check smokes (T2) skip unless the Kokoro model is installed.
final class SherpaTTSEngineTests: XCTestCase {
    private var defaultSpec: LocalModelSpec { LocalModelRegistry.defaultTTS }

    // MARK: - T1 (no model needed)

    func testMissingModelDirThrowsNotInstalled() {
        let empty = FileManager.default.temporaryDirectory
            .appendingPathComponent("kokoro-missing-\(UUID().uuidString)", isDirectory: true)
        XCTAssertThrowsError(try SherpaTTSEngine(modelDir: empty)) { error in
            XCTAssertEqual(error as? TTSError, .modelNotInstalled)
        }
    }

    // MARK: - T2 (gated on installed model)

    func testEmptyTextThrowsEmptyText() async throws {
        try XCTSkipUnless(defaultSpec.isInstalled, "Kokoro not installed; skipping")
        let engine = try SherpaTTSEngine(modelDir: defaultSpec.storagePath)
        do {
            _ = try await engine.synthesize("   \n  ")
            XCTFail("expected emptyText")
        } catch let error as TTSError {
            XCTAssertEqual(error, .emptyText)
        }
    }

    func testSynthesizeProducesPlausibleAudio() async throws {
        try XCTSkipUnless(defaultSpec.isInstalled, "Kokoro not installed; skipping synth smoke")
        let engine = try SherpaTTSEngine(modelDir: defaultSpec.storagePath)
        let speech = try await engine.synthesize("Hello there world.")
        XCTAssertFalse(speech.samples.isEmpty)
        XCTAssertEqual(speech.sampleRate, 24_000)
        XCTAssertNil(speech.providerTiming, "on-device Kokoro has no native word timing")
        XCTAssertGreaterThan(speech.duration, 0.3)
        XCTAssertLessThan(speech.duration, 6.0)
        print("Kokoro synth → \(speech.samples.count) samples, \(speech.duration)s @ \(speech.sampleRate)Hz")
    }

    /// Repeated calls on one cached engine don't crash / leak (keep-alive path).
    func testRepeatedSynthIsStable() async throws {
        try XCTSkipUnless(defaultSpec.isInstalled, "Kokoro not installed; skipping")
        let engine = try SherpaTTSEngine(modelDir: defaultSpec.storagePath)
        for _ in 0..<3 {
            let speech = try await engine.synthesize("Quick check.")
            XCTAssertFalse(speech.samples.isEmpty)
        }
    }

    func testSpeedChangesDuration() async throws {
        try XCTSkipUnless(defaultSpec.isInstalled, "Kokoro not installed; skipping speed smoke")
        let engine = try SherpaTTSEngine(modelDir: defaultSpec.storagePath)
        let normal = try await engine.synthesize("Hello there world.", speed: 1.0)
        let slow = try await engine.synthesize("Hello there world.", speed: 0.7)
        let fast = try await engine.synthesize("Hello there world.", speed: 1.5)
        XCTAssertGreaterThan(slow.duration, normal.duration, "0.7× should be longer")
        XCTAssertLessThan(fast.duration, normal.duration, "1.5× should be shorter")
    }

    func testTTSSelfCheckOnInstalledModel() async throws {
        try XCTSkipUnless(defaultSpec.isInstalled, "Kokoro not installed; skipping self-check")
        let report = try await LocalModelSelfCheck.runTTS(defaultSpec)
        XCTAssertGreaterThan(report.audioSeconds, 0)
        XCTAssertEqual(report.sampleRate, 24_000)
        print("TTS self-check → \(report.summary)")
    }
}
