import CoreGraphics
import Foundation

// MARK: - Cloud OCR · Mistral OCR provider
//
// Dedicated document OCR (`mistral-ocr-latest`): strong on PDFs / paper bodies, returns Markdown.
// Interface per the community plugin poyih/bob-plugin-mistral-ocr and Mistral docs:
// `POST {apiURL}/v1/ocr`, Bearer auth, body `{model, document:{type:"image_url", image_url:"data:…"}}`,
// resp `{pages:[{markdown}]}`. BYOK-direct (the app calls Mistral directly; key in Keychain) — the
// retired thin backend is no longer in the loop. Cloud returns flowed text with no per-line boxes,
// so `regions` is empty.

public struct MistralOCRProvider: OCRProvider {

    public static let engineID = "mistral-ocr"

    public let id = MistralOCRProvider.engineID
    public let displayName = "云端 · Mistral OCR"

    public typealias Transcriber = @Sendable (_ imageData: Data, _ mimeType: String) async throws -> String

    private let transcribe: Transcriber

    /// Inject a transcriber directly (tests / custom backend).
    public init(transcribe: @escaping Transcriber) {
        self.transcribe = transcribe
    }

    /// Convenience: a key closure issues the real request. Empty key → throws `.notConfigured`
    /// without touching the network.
    public init(
        apiKeyProvider: @escaping @Sendable () -> String?,
        apiURL: String = "https://api.mistral.ai",
        model: String = "mistral-ocr-latest",
        keepMarkdown: Bool = false,
        session: URLSession = .shared
    ) {
        self.transcribe = { imageData, mimeType in
            guard let key = apiKeyProvider()?.trimmingCharacters(in: .whitespaces), !key.isEmpty else {
                throw CloudOCRError.notConfigured
            }
            guard let url = Self.endpoint(apiURL: apiURL) else { throw CloudOCRError.notConfigured }

            var request = URLRequest(url: url, timeoutInterval: 90)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            let dataURL = OCRImageCodec.dataURL(from: imageData, mimeType: mimeType)
            request.httpBody = try Self.encodeRequestBody(model: model, imageDataURL: dataURL)

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw CloudOCRError.http(-1) }
            guard (200..<300).contains(http.statusCode) else { throw CloudOCRError.http(http.statusCode) }
            return try Self.parseOCRResponse(data, keepMarkdown: keepMarkdown)
        }
    }

    public func recognize(_ image: CGImage) async throws -> OCRResult {
        guard let png = OCRImageCodec.pngData(from: image) else { throw CloudOCRError.encoding }
        let text = try await transcribe(png, "image/png")
        return OCRResult(text: text, regions: [], languages: ["auto"], textStructure: .flowedText)
    }

    // MARK: - Pure seams (unit-testable)

    static func endpoint(apiURL: String) -> URL? {
        let base = apiURL.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        return URL(string: base + "/v1/ocr")
    }

    private struct OCRRequestBody: Encodable {
        let model: String
        let document: Document
        struct Document: Encodable {
            let type: String
            let image_url: String
        }
    }

    static func encodeRequestBody(model: String, imageDataURL: String) throws -> Data {
        do {
            return try JSONEncoder().encode(OCRRequestBody(
                model: model,
                document: .init(type: "image_url", image_url: imageDataURL)))
        } catch {
            throw CloudOCRError.encoding
        }
    }

    private struct OCRResponseBody: Decodable {
        let pages: [Page]?
        struct Page: Decodable { let markdown: String? }
    }

    /// Join non-empty pages (keep Markdown or strip to plain text), blank-line separated.
    static func parseOCRResponse(_ data: Data, keepMarkdown: Bool) throws -> String {
        guard let body = try? JSONDecoder().decode(OCRResponseBody.self, from: data) else {
            throw CloudOCRError.emptyText
        }
        let pages = (body.pages ?? [])
            .compactMap { $0.markdown }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { keepMarkdown ? $0 : MarkdownPlainText.from($0) }
        return pages.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
