import CoreGraphics
import Foundation

struct PaddleOCRRecognizer {
    private let session: PaddleORTSession
    private let characters: [String]

    init(model: PaddleOCRModel) throws {
        session = try PaddleORTSession(modelPath: model.recModel.path, threadCount: 4)
        characters = model.characters
    }

    func recognize(_ image: CGImage) throws -> (text: String, confidence: Float) {
        let input = try PaddleOCRImage(cgImage: image)
        let (data, shape) = input.recognitionTensor()
        let tensor = try session.run(withFloat: data, shape: shape)
        let floats = Self.floats(from: tensor.floatData)
        let dims = tensor.shape.map { $0.intValue }
        guard dims.count >= 3 else { return ("", 0) }
        let timeSteps = dims[dims.count - 2]
        let classes = dims[dims.count - 1]
        guard timeSteps > 0, classes > 0, floats.count >= timeSteps * classes else {
            return ("", 0)
        }
        return decode(floats: floats, timeSteps: timeSteps, classes: classes)
    }

    private func decode(floats: [Float], timeSteps: Int, classes: Int) -> (String, Float) {
        var text = ""
        var previous = -1
        var probs: [Float] = []
        for t in 0..<timeSteps {
            let offset = t * classes
            var best = 0
            var bestValue = floats[offset]
            for c in 1..<classes {
                let v = floats[offset + c]
                if v > bestValue {
                    best = c
                    bestValue = v
                }
            }
            if best != 0, best != previous {
                let charIndex = best - 1
                if charIndex >= 0, charIndex < characters.count {
                    text.append(characters[charIndex])
                    probs.append(softmaxProbability(floats, offset: offset, classes: classes, best: best))
                }
            }
            previous = best
        }
        let confidence = probs.isEmpty ? 0 : probs.reduce(0, +) / Float(probs.count)
        return (text.trimmingCharacters(in: .whitespacesAndNewlines), confidence)
    }

    private func softmaxProbability(_ values: [Float], offset: Int, classes: Int, best: Int) -> Float {
        let maxValue = (0..<classes).map { values[offset + $0] }.max() ?? 0
        var denom: Float = 0
        for c in 0..<classes {
            denom += exp(values[offset + c] - maxValue)
        }
        guard denom > 0 else { return 0 }
        return exp(values[offset + best] - maxValue) / denom
    }

    private static func floats(from data: Data) -> [Float] {
        data.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Float.self))
        }
    }
}
