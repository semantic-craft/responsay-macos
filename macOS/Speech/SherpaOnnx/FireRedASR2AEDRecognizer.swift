import Foundation
import OSLog

/// In-process offline ASR via sherpa-onnx + FireRedASR2 AED int8. Whole-utterance
/// like SenseVoice/Qwen3-ASR, but uses the FireRed encoder/decoder pair for
/// higher-quality Chinese + English and Chinese dialect/accent recognition.
/// No backend, no Python, no network at runtime.
///
/// `@unchecked Sendable`: used sequentially (one decode at a time), so it can be
/// cached on the main actor and decoded on a background task.
final class FireRedASR2AEDRecognizer: @unchecked Sendable {
    enum File {
        static let encoder = "encoder.int8.onnx"
        static let decoder = "decoder.int8.onnx"
        static let tokens = "tokens.txt"
    }

    enum LoadError: Error, CustomStringConvertible {
        case missingFile(String)

        var description: String {
            switch self { case .missingFile(let p): "FireRedASR2 AED model file not found: \(p)" }
        }
    }

    private let recognizer: SherpaOnnxOfflineRecognizer
    private static let log = Logger(
        subsystem: "com.semanticcraft.responsay.mac", category: "firered-asr2-aed")

    init(modelDir: URL, numThreads: Int = 2) throws {
        let encoder = modelDir.appendingPathComponent(File.encoder)
        let decoder = modelDir.appendingPathComponent(File.decoder)
        let tokens = modelDir.appendingPathComponent(File.tokens)
        for file in [encoder, decoder, tokens] where !FileManager.default.fileExists(atPath: file.path) {
            throw LoadError.missingFile(file.path)
        }

        var config = sherpaOnnxOfflineRecognizerConfig(
            featConfig: sherpaOnnxFeatureConfig(sampleRate: 16_000, featureDim: 80),
            modelConfig: sherpaOnnxOfflineModelConfig(
                tokens: tokens.path,
                numThreads: numThreads,
                fireRedAsr: sherpaOnnxOfflineFireRedAsrModelConfig(
                    encoder: encoder.path,
                    decoder: decoder.path)))
        recognizer = try SherpaOnnxOfflineRecognizer(config: &config)
        Self.log.info("FireRedASR2 AED recognizer loaded from \(modelDir.lastPathComponent, privacy: .public)")
    }
}

extension FireRedASR2AEDRecognizer: OfflineSherpaRecognizer {
    func transcribeText(_ samples: [Float], sampleRate: Int = 16_000) throws -> String {
        try recognizer.decode(samples: samples, sampleRate: sampleRate).text
    }
}
