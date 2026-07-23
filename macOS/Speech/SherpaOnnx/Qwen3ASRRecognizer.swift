import Foundation
import OSLog

/// In-process offline ASR via sherpa-onnx + Qwen3-ASR (0.6B int8). Whole-utterance
/// like SenseVoice, but uses conv-frontend + encoder/decoder + a tokenizer dir.
/// Strong multilingual + Chinese/dialect + code-switching. No backend, no network.
///
/// `@unchecked Sendable`: used sequentially (one decode at a time), so it can be
/// cached on the main actor and decoded on a background task.
final class Qwen3ASRRecognizer: @unchecked Sendable {
    enum File {
        static let convFrontend = "conv_frontend.onnx"
        static let encoder = "encoder.int8.onnx"
        static let decoder = "decoder.int8.onnx"
        static let tokenizerDir = "tokenizer"
        static let tokenizerVocab = "tokenizer/vocab.json"
    }

    enum LoadError: Error, CustomStringConvertible {
        case missingFile(String)
        var description: String {
            switch self { case .missingFile(let p): "Qwen3-ASR model file not found: \(p)" }
        }
    }

    private let recognizer: SherpaOnnxOfflineRecognizer
    private static let log = Logger(
        subsystem: "com.semanticcraft.responsay.mac", category: "qwen3-asr")

    /// Project biasing terms into sherpa-onnx's Qwen3-ASR `hotwords` model-config field, which it
    /// parses as a comma-separated (ASCII `,`) UTF-8 list (c-api.h `SherpaOnnxOfflineQwen3ASRModelConfig`).
    /// Embedded commas are stripped so a single term can't corrupt the separator, and empties dropped.
    /// Terms arrive already trimmed / deduped / capped upstream (`HotwordStore.flattened()` ≤40), so no
    /// further cap is needed within Qwen3's 512-token decode budget.
    static func hotwordsString(from terms: [String]) -> String {
        terms
            .map { $0.replacingOccurrences(of: ",", with: "") }
            .filter { !$0.isEmpty }
            .joined(separator: ",")
    }

    /// - Parameter hotwords: comma-separated soft biasing list (see `hotwordsString(from:)`). sherpa
    ///   tokenizes it into the Qwen3 decoder's chat **system prompt** (the same channel as the cloud
    ///   qwen3-asr-flash 定制化识别 Context, 修法 A) — verified against k2-fsa source @ v1.13.2.
    ///   Baked in at build via the model-config default, so it refreshes whenever the cached
    ///   recognizer is rebuilt (per the `localEngineTTL` keep-loaded cycle), not per utterance.
    ///   Empty = baseline decode.
    // ponytail: build-time bake → ≤TTL (default 5 min) staleness after a newly-learned term.
    // Upgrade path if that ever matters: set the per-stream "hotwords" option
    // (`SherpaOnnxOfflineStreamSetOption(stream, "hotwords", …)`, which overrides the config default
    // per-decode) — refreshes every utterance like the cloud path, at the cost of threading terms
    // through the shared `OfflineSherpaRecognizer.transcribeText` decode seam.
    init(modelDir: URL, numThreads: Int = 2, hotwords: String = "") throws {
        let conv = modelDir.appendingPathComponent(File.convFrontend)
        let encoder = modelDir.appendingPathComponent(File.encoder)
        let decoder = modelDir.appendingPathComponent(File.decoder)
        let tokenizer = modelDir.appendingPathComponent(File.tokenizerDir, isDirectory: true)
        let vocab = modelDir.appendingPathComponent(File.tokenizerVocab)
        for f in [conv, encoder, decoder, vocab]
        where !FileManager.default.fileExists(atPath: f.path) {
            throw LoadError.missingFile(f.path)
        }

        var config = sherpaOnnxOfflineRecognizerConfig(
            featConfig: sherpaOnnxFeatureConfig(sampleRate: 16_000, featureDim: 80),
            modelConfig: sherpaOnnxOfflineModelConfig(
                tokens: "",   // Qwen3-ASR carries its tokenizer dir instead of tokens.txt
                numThreads: numThreads,
                qwen3Asr: sherpaOnnxOfflineQwen3ASRModelConfig(
                    convFrontend: conv.path,
                    encoder: encoder.path,
                    decoder: decoder.path,
                    tokenizer: tokenizer.path,
                    hotwords: hotwords)))
        recognizer = try SherpaOnnxOfflineRecognizer(config: &config)
        Self.log.info(
            "Qwen3-ASR recognizer loaded from \(modelDir.lastPathComponent, privacy: .public), hotwords=\(hotwords.isEmpty ? 0 : hotwords.split(separator: ",").count, privacy: .public)")
    }
}

extension Qwen3ASRRecognizer: OfflineSherpaRecognizer {
    func transcribeText(_ samples: [Float], sampleRate: Int = 16_000) throws -> String {
        try recognizer.decode(samples: samples, sampleRate: sampleRate).text
    }
}
