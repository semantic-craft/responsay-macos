import Foundation
import OSLog

/// In-process offline punctuation via sherpa-onnx CT-Transformer. Loads `model.int8.onnx` from a
/// model directory and restores punctuation locally — no network, no LLM. Used by the 如实输入
/// (raw / verbatim) path so dictation from a punctuation-less offline ASR still gets punctuation.
///
/// `@unchecked Sendable`: the underlying sherpa-onnx punctuation handle is used sequentially (one
/// `addPunct` at a time), guarded by the `LocalPunctuationEngine` actor.
final class CTTransformerPunctuator: @unchecked Sendable {
    enum File { static let model = "model.int8.onnx" }

    enum LoadError: Error, CustomStringConvertible {
        case missingFile(String)
        case createFailed

        var description: String {
            switch self {
            case .missingFile(let path): "CT-Transformer punctuation model not found: \(path)"
            case .createFailed: "sherpa-onnx failed to create the punctuation handle"
            }
        }
    }

    private let wrapper: SherpaOnnxOfflinePunctuationWrapper
    private static let log = Logger(
        subsystem: "com.semanticcraft.responsay.mac", category: "punct-ct-transformer")

    init(modelDir: URL, numThreads: Int = 1) throws {
        let model = modelDir.appendingPathComponent(File.model)
        guard FileManager.default.fileExists(atPath: model.path) else {
            throw LoadError.missingFile(model.path)
        }
        let modelConfig = sherpaOnnxOfflinePunctuationModelConfig(
            ctTransformer: model.path, numThreads: numThreads)
        var config = sherpaOnnxOfflinePunctuationConfig(model: modelConfig)
        let wrapper = SherpaOnnxOfflinePunctuationWrapper(config: &config)
        guard wrapper.ptr != nil else { throw LoadError.createFailed }
        self.wrapper = wrapper
        Self.log.info("CT-Transformer punctuation loaded from \(modelDir.lastPathComponent, privacy: .public)")
    }

    /// Restore punctuation/capitalization for one utterance (blocking CPU work — call off-main).
    func addPunctuation(_ text: String) -> String {
        wrapper.addPunct(text: text)
    }
}
