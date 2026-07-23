import Foundation
import OSLog

/// In-process offline ASR via sherpa-onnx + Fun-ASR Nano (Alibaba Tongyi FunAudioLLM).
/// LLM-based whole-utterance ASR: an encoder-adaptor feeds a Qwen3-0.6B LLM decoder
/// (so the model carries a `Qwen3-0.6B/` tokenizer dir, not a `tokens.txt`). Broad
/// Chinese dialect + accent coverage. No backend, no Python, no network at runtime.
///
/// `@unchecked Sendable`: used sequentially (one decode at a time), so it can be
/// cached on the main actor and decoded on a background task.
final class FunASRNanoRecognizer: @unchecked Sendable {
    enum File {
        static let encoderAdaptor = "encoder_adaptor.int8.onnx"
        static let llm = "llm.fp16.onnx"
        static let embedding = "embedding.int8.onnx"
        static let tokenizerDir = "Qwen3-0.6B"
        static let tokenizerJSON = "Qwen3-0.6B/tokenizer.json"
    }

    enum LoadError: Error, CustomStringConvertible {
        case missingFile(String)
        var description: String {
            switch self { case .missingFile(let p): "Fun-ASR Nano model file not found: \(p)" }
        }
    }

    private let recognizer: SherpaOnnxOfflineRecognizer
    private static let log = Logger(
        subsystem: "com.semanticcraft.responsay.mac", category: "funasr-nano")

    init(modelDir: URL, numThreads: Int = 2) throws {
        let encoderAdaptor = modelDir.appendingPathComponent(File.encoderAdaptor)
        let llm = modelDir.appendingPathComponent(File.llm)
        let embedding = modelDir.appendingPathComponent(File.embedding)
        let tokenizer = modelDir.appendingPathComponent(File.tokenizerDir, isDirectory: true)
        let tokenizerJSON = modelDir.appendingPathComponent(File.tokenizerJSON)
        for f in [encoderAdaptor, llm, embedding, tokenizerJSON]
        where !FileManager.default.fileExists(atPath: f.path) {
            throw LoadError.missingFile(f.path)
        }

        var config = sherpaOnnxOfflineRecognizerConfig(
            featConfig: sherpaOnnxFeatureConfig(sampleRate: 16_000, featureDim: 80),
            modelConfig: sherpaOnnxOfflineModelConfig(
                tokens: "",   // Fun-ASR Nano carries the Qwen3 tokenizer dir instead of tokens.txt
                numThreads: numThreads,
                funasrNano: sherpaOnnxOfflineFunASRNanoModelConfig(
                    encoderAdaptor: encoderAdaptor.path,
                    llm: llm.path,
                    embedding: embedding.path,
                    tokenizer: tokenizer.path)))
        recognizer = try SherpaOnnxOfflineRecognizer(config: &config)
        Self.log.info("Fun-ASR Nano recognizer loaded from \(modelDir.lastPathComponent, privacy: .public)")
    }
}

extension FunASRNanoRecognizer: OfflineSherpaRecognizer {
    func transcribeText(_ samples: [Float], sampleRate: Int = 16_000) throws -> String {
        try recognizer.decode(samples: samples, sampleRate: sampleRate).text
    }
}
