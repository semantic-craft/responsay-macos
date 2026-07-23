import Foundation
import OSLog

/// A sherpa-onnx offline (whole-utterance) ASR recognizer. Implemented per model
/// family (SenseVoice, Qwen3-ASR, …) so one capture service can drive any of them.
protocol OfflineSherpaRecognizer: AnyObject, Sendable {
    func transcribeText(_ samples: [Float], sampleRate: Int) throws -> String
}

/// Thin Swift facade over the sherpa-onnx offline recognizer for the SenseVoice
/// model. Loads `model.int8.onnx` + `tokens.txt` from a model directory and
/// transcribes 16 kHz mono PCM **in-process** — no network, no Node backend.
///
/// This is the offline (whole-utterance) path: feed the full recording after the
/// user stops talking. Streaming partials are a separate concern (Zipformer).
///
/// `@unchecked Sendable`: the underlying sherpa-onnx `OfflineRecognizer` is only
/// ever used sequentially (one `decode` at a time, each creating its own stream),
/// so the instance can be cached on the main actor and decoded on a background
/// task without data races.
final class SenseVoiceRecognizer: @unchecked Sendable {
    /// File names inside a SenseVoice model directory (sherpa-onnx layout).
    enum File {
        static let model = "model.int8.onnx"
        static let tokens = "tokens.txt"
    }

    enum LoadError: Error, CustomStringConvertible {
        case missingFile(String)

        var description: String {
            switch self {
            case .missingFile(let path): "SenseVoice model file not found: \(path)"
            }
        }
    }

    private let recognizer: SherpaOnnxOfflineRecognizer
    private static let log = Logger(
        subsystem: "com.semanticcraft.responsay.mac", category: "SenseVoice")

    /// - Parameters:
    ///   - modelDir: directory holding `model.int8.onnx` and `tokens.txt`.
    ///   - language: "" for auto-detect, or one of zh/en/ja/ko/yue.
    ///   - useITN: inverse text normalization (spoken digits/punctuation → written form).
    ///   - numThreads: ONNX intra-op threads.
    init(modelDir: URL, language: String = "", useITN: Bool = true, numThreads: Int = 2) throws {
        let model = modelDir.appendingPathComponent(File.model)
        let tokens = modelDir.appendingPathComponent(File.tokens)
        for file in [model, tokens] where !FileManager.default.fileExists(atPath: file.path) {
            throw LoadError.missingFile(file.path)
        }

        var config = sherpaOnnxOfflineRecognizerConfig(
            featConfig: sherpaOnnxFeatureConfig(sampleRate: 16_000, featureDim: 80),
            modelConfig: sherpaOnnxOfflineModelConfig(
                tokens: tokens.path,
                numThreads: numThreads,
                senseVoice: sherpaOnnxOfflineSenseVoiceModelConfig(
                    model: model.path,
                    language: language,
                    useInverseTextNormalization: useITN
                )
            )
        )
        recognizer = try SherpaOnnxOfflineRecognizer(config: &config)
        Self.log.info("SenseVoice recognizer loaded from \(modelDir.lastPathComponent, privacy: .public)")
    }

    /// Transcribe mono PCM samples normalized to [-1, 1]. `sampleRate` must match
    /// the model (16 kHz). Blocking CPU work — call off the main thread.
    ///
    /// Note: with auto language ("") SenseVoice can drop the opening character on
    /// clips that start abruptly (the language tag consumes the first frame).
    /// Real mic recordings have leading silence so this doesn't bite in practice;
    /// leading-silence padding was tried and made accuracy worse, so it's avoided.
    func transcribe(samples: [Float], sampleRate: Int = 16_000) throws -> SenseVoiceResult {
        let r = try recognizer.decode(samples: samples, sampleRate: sampleRate)
        return SenseVoiceResult(text: r.text, language: r.lang, emotion: r.emotion, event: r.event)
    }
}

extension SenseVoiceRecognizer: OfflineSherpaRecognizer {
    func transcribeText(_ samples: [Float], sampleRate: Int = 16_000) throws -> String {
        try transcribe(samples: samples, sampleRate: sampleRate).text
    }
}

/// Plain value carrying what SenseVoice returns. `language`/`emotion`/`event`
/// are SenseVoice extras (empty for other models).
struct SenseVoiceResult: Equatable, Sendable {
    let text: String
    let language: String
    let emotion: String
    let event: String
}
