import CoreGraphics
import Foundation
import ResponsayCore

struct ResidentPaddleOCRProvider: OCRProvider, @unchecked Sendable {
    let id = PaddleOCRProvider.engineID
    let displayName = "本机 · PaddleOCR v6 Small"

    private let engine: PaddleOCRResidentEngine

    @MainActor
    init(engine: PaddleOCRResidentEngine = .shared) {
        self.engine = engine
    }

    func recognize(_ image: CGImage) async throws -> OCRResult {
        let provider = try await engine.beginRecognition()
        do {
            let result = try await provider.recognize(image)
            await engine.finishRecognition()
            return result
        } catch {
            await engine.finishRecognition()
            throw error
        }
    }
}
