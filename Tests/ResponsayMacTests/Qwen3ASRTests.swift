import AVFoundation
import XCTest
@testable import ResponsayMac

final class Qwen3ASRTests: XCTestCase {
    private let spec = LocalModelSpec.qwen3ASR

    func testRegistryHasQwen3Downloadable() {
        XCTAssertTrue(LocalModelRegistry.downloadable.map(\.id).contains(ASREngine.qwen3LocalASR.rawValue))
        XCTAssertEqual(spec.family, .qwen3Asr)
        XCTAssertEqual(spec.capability, .asr)
        XCTAssertEqual(spec.download?.sha256.count, 64)
        XCTAssertTrue(LocalModelSelfCheck.supports(.qwen3Asr))
    }

    /// Real transcription against the installed Qwen3-ASR model (skips if absent).
    func testTranscribesSample() throws {
        try XCTSkipUnless(spec.isInstalled, "Qwen3-ASR not installed; skipping")
        let recognizer = try Qwen3ASRRecognizer(modelDir: spec.storagePath)

        let wav = spec.storagePath.appendingPathComponent("test_wavs/codeswitch.wav")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: wav.path), "sample missing")
        let file = try AVAudioFile(forReading: wav)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let channel = try XCTUnwrap(buffer.floatChannelData)
        let samples = Array(UnsafeBufferPointer(start: channel[0], count: Int(buffer.frameLength)))

        let text = try recognizer.transcribeText(samples, sampleRate: 16_000)
        print("Qwen3-ASR codeswitch.wav → \(text)")
        XCTAssertFalse(text.isEmpty, "Qwen3-ASR produced no transcript")
    }

    /// Self-check works for the Qwen3 family too (rtfX vs expected).
    func testSelfCheck() throws {
        try XCTSkipUnless(spec.isInstalled, "Qwen3-ASR not installed; skipping")
        let report = try LocalModelSelfCheck.runASR(spec)
        print("Qwen3-ASR self-check → \(report.summary)")
        XCTAssertFalse(report.transcript.isEmpty)
        XCTAssertGreaterThan(report.realtimeFactor, 0)
    }
}
