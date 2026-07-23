import CoreGraphics
import Foundation
import ResponsayCore

final class PaddleOCRProvider: OCRProvider, @unchecked Sendable {
    static let engineID = "local-paddleocr-v6-small"

    let id = PaddleOCRProvider.engineID
    let displayName = "本机 · PaddleOCR v6 Small"

    private let detector: PaddleOCRDetector
    private let recognizer: PaddleOCRRecognizer

    init(modelDir: URL) throws {
        let model = try PaddleOCRModel(root: modelDir)
        detector = try PaddleOCRDetector(model: model)
        recognizer = try PaddleOCRRecognizer(model: model)
    }

    func recognize(_ image: CGImage) async throws -> OCRResult {
        let boxes = try detector.detect(image)
        guard !boxes.isEmpty else {
            return OCRResult(text: "", regions: [], languages: ["auto"])
        }

        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        var regions: [OCRRegion] = []
        for box in boxes {
            let rect = box.rect.integral.intersection(bounds)
            guard rect.width > 1, rect.height > 1,
                  let crop = image.cropping(to: rect) else { continue }
            let result = try recognizer.recognize(crop)
            guard !result.text.isEmpty else { continue }
            regions.append(OCRRegion(
                text: result.text,
                boundingBox: rect,
                confidence: min(1, max(result.confidence, box.confidence))))
        }
        return OCRResult(regions: regions, languages: ["auto"])
    }
}
