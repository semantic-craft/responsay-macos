import AVFoundation
import XCTest
@testable import ResponsayMac

final class FunAsrNanoTests: XCTestCase {
    private let spec = LocalModelSpec.funAsrNano

    func testFunAsrNanoIsSelectableAndDownloadable() {
        // #387: official Alibaba Tongyi FunAudioLLM model, broad Chinese-dialect coverage.
        // Default precision = fp16 (encoder/embedding int8 + llm fp16).
        XCTAssertTrue(ASREngine.selectableCases.contains(.funAsrNanoLocal))
        XCTAssertTrue(LocalModelRegistry.downloadable.map(\.id).contains(ASREngine.funAsrNanoLocal.rawValue))
        XCTAssertEqual(spec.family, .funAsrNano)
        XCTAssertEqual(spec.capability, .asr)
        XCTAssertEqual(spec.download?.sha256, "a07a996361aa2f8b2c4f47861fe01953b5509664efa3392b734580b1eeb362e3")
        XCTAssertEqual(spec.download?.byteSize, 1_030_076_153)
        XCTAssertEqual(
            spec.download?.requiredFiles,
            ["encoder_adaptor.int8.onnx", "llm.fp16.onnx", "embedding.int8.onnx", "Qwen3-0.6B/tokenizer.json"])
        XCTAssertTrue(LocalModelSelfCheck.supports(.funAsrNano))
    }

    /// Real transcription against the installed Fun-ASR Nano model (skips if absent).
    func testTranscribesSample() throws {
        try XCTSkipUnless(spec.isInstalled, "Fun-ASR Nano not installed; skipping")
        let recognizer = try FunASRNanoRecognizer(modelDir: spec.storagePath)

        let wav = spec.storagePath.appendingPathComponent("test_wavs/dia_sh.wav")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: wav.path), "sample missing")
        let file = try AVAudioFile(forReading: wav)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let channel = try XCTUnwrap(buffer.floatChannelData)
        let samples = Array(UnsafeBufferPointer(start: channel[0], count: Int(buffer.frameLength)))

        let text = try recognizer.transcribeText(samples, sampleRate: 16_000)
        print("Fun-ASR Nano dia_sh.wav → \(text)")
        XCTAssertFalse(text.isEmpty, "Fun-ASR Nano produced no transcript")
    }

    /// Self-check works for the Fun-ASR Nano family too.
    func testSelfCheck() throws {
        try XCTSkipUnless(spec.isInstalled, "Fun-ASR Nano not installed; skipping")
        let report = try LocalModelSelfCheck.runASR(spec)
        print("Fun-ASR Nano self-check → \(report.summary)")
        XCTAssertFalse(report.transcript.isEmpty)
        XCTAssertGreaterThan(report.realtimeFactor, 0)
    }

    /// Real download + checksum + extraction + transcription smoke. Off by default
    /// because the official archive is ~1 GB; run with RUN_NETWORK_TESTS=1.
    func testNetworkDownloadAndSelfCheck() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_NETWORK_TESTS"] == "1",
            "Fun-ASR Nano network smoke disabled (set RUN_NETWORK_TESTS=1 to run)")

        if !spec.isInstalled {
            try await LocalModelDownloader.install(spec) { _ in }
        }
        let report = try LocalModelSelfCheck.runASR(spec)
        print("Fun-ASR Nano network self-check → \(report.summary) transcript=\(report.transcript)")
        XCTAssertFalse(report.transcript.isEmpty)
        XCTAssertGreaterThan(report.realtimeFactor, 0)
    }
}
