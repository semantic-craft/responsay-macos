import CoreGraphics
import Foundation
import Vision

// MARK: - 070 Snap & Translate · on-device Apple Vision OCR (default provider)
//
// ADR-0005: on-device Apple Vision (`VNRecognizeTextRequest`, `.accurate`, language correction,
// zh-Hans + en-US), free and offline, behind the `OCRProvider` seam so a cloud vision-LLM
// (issue 074) can be swapped in. Vision is available on both macOS and iOS, so this lives in
// Core (no AppKit) and the package stays cross-platform. The synchronous Vision kernel is wrapped
// as `async` to satisfy the protocol; recognition is CPU-bound and runs off the caller's actor.

public struct AppleVisionOCRProvider: OCRProvider {
    public let id = "apple-vision"
    public let displayName = "Apple Vision（本机）"

    /// Recognition languages, default 简体中文 + 英文 (covers mixed legal/English-coach screens).
    public let recognitionLanguages: [String]

    public init(recognitionLanguages: [String] = ["zh-Hans", "en-US"]) {
        self.recognitionLanguages = recognitionLanguages
    }

    public func recognize(_ image: CGImage) async throws -> OCRResult {
        let languages = recognitionLanguages
        // Vision's `perform` is synchronous + CPU-bound; hop off the calling actor so a Snap &
        // Translate from the main actor never blocks the UI.
        return try await Task.detached(priority: .userInitiated) {
            try Self.recognizeSync(image, languages: languages)
        }.value
    }

    /// The actual Vision call, factored out so it is testable and reusable.
    static func recognizeSync(_ image: CGImage, languages: [String]) throws -> OCRResult {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate          // accurate > fast for legal/dense text
        request.usesLanguageCorrection = true
        request.recognitionLanguages = languages

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw OCRError.recognitionFailed(error.localizedDescription)
        }

        let imageSize = CGSize(width: image.width, height: image.height)
        let regions: [OCRRegion] = (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return OCRRegion(
                text: candidate.string,
                boundingBox: OCRGeometry.pixelRect(
                    fromNormalized: observation.boundingBox, imageSize: imageSize),
                confidence: candidate.confidence)
        }
        return OCRResult(regions: regions, languages: languages)
    }
}
