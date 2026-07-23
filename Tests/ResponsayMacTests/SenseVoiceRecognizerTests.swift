import AVFoundation
import XCTest
@testable import ResponsayMac

/// End-to-end smoke for the in-process SenseVoice offline recognizer.
///
/// Needs the model weights on disk (gitignored, ~240MB). Fetch with:
///   gh release download asr-models --repo k2-fsa/sherpa-onnx \
///     --pattern "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09.tar.bz2"
/// extracted under `models/`. When absent the test is skipped, not failed, so CI
/// without the weights stays green. This is a dev integration smoke, not a unit test.
final class SenseVoiceRecognizerTests: XCTestCase {
    /// Repo root, derived from this source file's location at build time.
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)        // …/Tests/ResponsayMacTests/SenseVoiceRecognizerTests.swift
            .deletingLastPathComponent()        // …/Tests/ResponsayMacTests
            .deletingLastPathComponent()        // …/Tests
            .deletingLastPathComponent()        // repo root
    }

    private var modelDir: URL {
        repoRoot.appendingPathComponent(
            "models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09")
    }

    private func requireModelDir() throws -> URL {
        let dir = modelDir
        let model = dir.appendingPathComponent(SenseVoiceRecognizer.File.model)
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: model.path),
            "SenseVoice weights not found at \(dir.path) — run the fetch step to enable this smoke.")
        return dir
    }

    /// Read a mono WAV into Float samples (AVAudioFile converts PCM16 → Float32).
    private func readSamples(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let channel = try XCTUnwrap(buffer.floatChannelData)
        return Array(UnsafeBufferPointer(start: channel[0], count: Int(buffer.frameLength)))
    }

    func testTranscribesChineseSample() throws {
        let dir = try requireModelDir()
        let wav = dir.appendingPathComponent("test_wavs/zh.wav")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: wav.path), "zh.wav missing")

        let recognizer = try SenseVoiceRecognizer(modelDir: dir, language: "zh")
        let samples = try readSamples(wav)
        XCTAssertFalse(samples.isEmpty, "decoded no audio samples")

        let result = try recognizer.transcribe(samples: samples)
        XCTAssertFalse(result.text.isEmpty, "SenseVoice returned empty transcript")
        // Real transcription, not garbage: this clip's canonical content.
        XCTAssertTrue(
            result.text.contains("开放时间"),
            "unexpected transcript (real content check failed): \(result.text)")
        // Contains CJK ideographs.
        XCTAssertTrue(
            result.text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) },
            "transcript has no Chinese characters: \(result.text)")
        // SenseVoice reports language as a tag like "<|zh|>" / "<|yue|>" (CJK family here).
        XCTAssertFalse(result.language.isEmpty, "expected a language tag from SenseVoice")
        print("SenseVoice zh.wav → \(result.text)  [lang=\(result.language)]")
    }
}
