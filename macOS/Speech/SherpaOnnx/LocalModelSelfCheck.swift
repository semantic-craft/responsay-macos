import AVFoundation
import Foundation
import ResponsayCore

/// Load & Test self-check (issue 162): loads an installed local ASR model,
/// transcribes its bundled sample, and reports real-time factor vs. expected.
struct ASRSelfCheckReport: Sendable, Equatable {
    let modelId: String
    let audioSeconds: Double
    let processSeconds: Double
    /// audioSeconds / processSeconds. >1 = faster than real time.
    let realtimeFactor: Double
    let expectedRealtimeFactor: Double?
    let transcript: String

    /// Pass if we have no target, or we hit at least half the rough target
    /// (the catalog figures are coarse engineering estimates, not guarantees).
    var meetsExpectation: Bool {
        guard let expected = expectedRealtimeFactor else { return true }
        return realtimeFactor >= expected * 0.5
    }

    var summary: String {
        let rtf = String(format: "%.1f", realtimeFactor)
        let exp = expectedRealtimeFactor.map { String(format: "%.0f", $0) } ?? "—"
        let mark = meetsExpectation ? "✓" : "⚠︎"
        return "\(mark) \(rtf)× 实时（期望 ≥\(exp)×）· \(Int(processSeconds * 1000))ms"
    }
}

/// TTS self-check (issue 202/203): synthesize a fixed phrase and report that the
/// installed Kokoro model produces plausible audio. The TTS parallel of `ASRSelfCheckReport`.
struct TTSSelfCheckReport: Sendable, Equatable {
    let modelId: String
    let audioSeconds: Double
    let processSeconds: Double
    let sampleRate: Int

    var summary: String {
        let dur = String(format: "%.2f", audioSeconds)
        return "✓ 合成 \(dur)s 音频 @ \(sampleRate)Hz · \(Int(processSeconds * 1000))ms"
    }
}

enum SelfCheckError: Error, CustomStringConvertible {
    case notInstalled
    case unsupportedFamily(ModelFamily)
    case sampleMissing
    case emptyTranscript
    case emptyAudio

    var description: String {
        switch self {
        case .notInstalled: "模型未安装。"
        case .unsupportedFamily(let f): "暂不支持该模型族的自检：\(f.rawValue)。"
        case .sampleMissing: "模型包内缺少测试音频（test_wavs）。"
        case .emptyTranscript: "自检转写为空,模型可能损坏,请重新下载。"
        case .emptyAudio: "自检合成为空,模型可能损坏,请重新下载。"
        }
    }
}

enum LocalModelSelfCheck {
    /// Families with an offline self-check (ASR recognizers + Kokoro TTS).
    static func supports(_ family: ModelFamily) -> Bool {
        family == .senseVoice || family == .fireRedAsrAed || family == .qwen3Asr
            || family == .funAsrNano || family == .kokoro
    }

    /// Fixed bilingual self-check phrase (exercises the en + zh Kokoro paths).
    static let ttsProbe = "Hello there. 你好，欢迎使用。"

    /// Run a TTS self-check: synthesize a fixed phrase and assert non-empty audio.
    /// Blocking CPU work behind `await` — call off the main actor.
    static func runTTS(_ spec: LocalModelSpec) async throws -> TTSSelfCheckReport {
        guard spec.isInstalled else { throw SelfCheckError.notInstalled }
        guard spec.family == .kokoro else { throw SelfCheckError.unsupportedFamily(spec.family) }
        let engine = try SherpaTTSEngine(modelDir: spec.storagePath)
        let start = Date()
        let speech = try await engine.synthesize(ttsProbe)
        let processSeconds = Date().timeIntervalSince(start)
        guard !speech.samples.isEmpty else { throw SelfCheckError.emptyAudio }
        return TTSSelfCheckReport(
            modelId: spec.id,
            audioSeconds: speech.duration,
            processSeconds: processSeconds,
            sampleRate: speech.sampleRate)
    }

    /// Run an ASR self-check. Blocking CPU work — call off the main actor.
    static func runASR(_ spec: LocalModelSpec) throws -> ASRSelfCheckReport {
        guard spec.isInstalled else { throw SelfCheckError.notInstalled }
        let recognizer = try makeRecognizer(for: spec)

        let sample = try firstSample(in: spec.storagePath)
        let samples = try readMonoSamples(sample)
        let audioSeconds = Double(samples.count) / 16_000.0

        let start = Date()
        let text = try recognizer.transcribeText(samples, sampleRate: 16_000)
        let processSeconds = Date().timeIntervalSince(start)
        guard !text.isEmpty else { throw SelfCheckError.emptyTranscript }

        let rtf = processSeconds > 0 ? audioSeconds / processSeconds : .infinity
        return ASRSelfCheckReport(
            modelId: spec.id,
            audioSeconds: audioSeconds,
            processSeconds: processSeconds,
            realtimeFactor: rtf,
            expectedRealtimeFactor: spec.expected.asrRealtimeFactor,
            transcript: text)
    }

    private static func makeRecognizer(for spec: LocalModelSpec) throws -> any OfflineSherpaRecognizer {
        switch spec.family {
        case .senseVoice: return try SenseVoiceRecognizer(modelDir: spec.storagePath)
        case .fireRedAsrAed: return try FireRedASR2AEDRecognizer(modelDir: spec.storagePath)
        case .qwen3Asr: return try Qwen3ASRRecognizer(modelDir: spec.storagePath)
        case .funAsrNano: return try FunASRNanoRecognizer(modelDir: spec.storagePath)
        default: throw SelfCheckError.unsupportedFamily(spec.family)
        }
    }

    /// First `.wav` under the model's `test_wavs/` (model packages ship samples).
    private static func firstSample(in modelDir: URL) throws -> URL {
        let dir = modelDir.appendingPathComponent("test_wavs", isDirectory: true)
        let wavs = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { $0.hasSuffix(".wav") }.sorted()
        guard let first = wavs.first else { throw SelfCheckError.sampleMissing }
        return dir.appendingPathComponent(first)
    }

    private static func readMonoSamples(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
            file.length > 0 else { return [] }
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: channel[0], count: Int(buffer.frameLength)))
    }
}
