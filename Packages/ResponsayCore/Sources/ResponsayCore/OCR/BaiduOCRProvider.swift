import CoreGraphics
import Foundation

// MARK: - Cloud OCR · Baidu OCR provider (general_basic / accurate_basic)
//
// Cheap, strong on Chinese. Two-step auth: `client_id`+`client_secret` → `access_token`, then call
// OCR with the token. OCR body is `application/x-www-form-urlencoded` `image=<base64 then urlencode>`,
// resp `{words_result:[{words}]}`. Endpoints per Baidu AI Cloud docs (aip.baidubce.com). BYOK-direct
// (key + secret in Keychain). Returns per-line text but no pixel boxes (Baidu `location` not taken
// here), so `regions` is empty.
//
// Note: this fetches a fresh token on every recognize (simplest). The token is valid ~30 days, so a
// future optimization could cache it to save one round-trip.

public struct BaiduOCRProvider: OCRProvider {

    public static let engineID = "baidu-ocr"

    public let id = BaiduOCRProvider.engineID
    public let displayName = "云端 · 百度 OCR"

    public typealias Transcriber = @Sendable (_ imageData: Data, _ mimeType: String) async throws -> String

    private let transcribe: Transcriber

    /// Inject a transcriber directly (tests / custom backend).
    public init(transcribe: @escaping Transcriber) {
        self.transcribe = transcribe
    }

    /// Convenience: API Key + Secret Key closure. Either empty → `.notConfigured` (no network).
    public init(
        credentialsProvider: @escaping @Sendable () -> (apiKey: String, secretKey: String)?,
        accurate: Bool = false,
        session: URLSession = .shared
    ) {
        self.transcribe = { imageData, _ in
            guard let cred = credentialsProvider(),
                  !cred.apiKey.trimmingCharacters(in: .whitespaces).isEmpty,
                  !cred.secretKey.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw CloudOCRError.notConfigured
            }
            let token = try await Self.fetchToken(
                apiKey: cred.apiKey, secretKey: cred.secretKey, session: session)
            guard let url = Self.ocrURL(accessToken: token, accurate: accurate) else {
                throw CloudOCRError.notConfigured
            }
            var request = URLRequest(url: url, timeoutInterval: 60)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Self.formBody(base64: imageData.base64EncodedString())

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw CloudOCRError.http(-1) }
            guard (200..<300).contains(http.statusCode) else { throw CloudOCRError.http(http.statusCode) }
            return try Self.parseOCRResponse(data)
        }
    }

    public func recognize(_ image: CGImage) async throws -> OCRResult {
        guard let png = OCRImageCodec.pngData(from: image) else { throw CloudOCRError.encoding }
        let text = try await transcribe(png, "image/png")
        return OCRResult(text: text, regions: [], languages: ["auto"], textStructure: .rawLines)
    }

    private static func fetchToken(apiKey: String, secretKey: String, session: URLSession) async throws -> String {
        guard let url = tokenURL(apiKey: apiKey, secretKey: secretKey) else {
            throw CloudOCRError.notConfigured
        }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CloudOCRError.token("鉴权请求失败")
        }
        return try parseToken(data)
    }

    // MARK: - Pure seams (unit-testable)

    static func tokenURL(apiKey: String, secretKey: String) -> URL? {
        var components = URLComponents(string: "https://aip.baidubce.com/oauth/2.0/token")
        components?.queryItems = [
            URLQueryItem(name: "grant_type", value: "client_credentials"),
            URLQueryItem(name: "client_id", value: apiKey),
            URLQueryItem(name: "client_secret", value: secretKey),
        ]
        return components?.url
    }

    static func ocrURL(accessToken: String, accurate: Bool) -> URL? {
        let path = accurate ? "accurate_basic" : "general_basic"
        return URL(string: "https://aip.baidubce.com/rest/2.0/ocr/v1/\(path)?access_token=\(accessToken)")
    }

    /// `image=<base64 then urlencode>` (Baidu requires the base64 to be percent-encoded).
    static func formBody(base64: String) -> Data {
        let encoded = base64.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? base64
        return Data("image=\(encoded)".utf8)
    }

    private struct TokenBody: Decodable {
        let access_token: String?
        let error: String?
    }

    static func parseToken(_ data: Data) throws -> String {
        guard let body = try? JSONDecoder().decode(TokenBody.self, from: data) else {
            throw CloudOCRError.token("无法解析鉴权响应")
        }
        if let error = body.error { throw CloudOCRError.token(error) }
        guard let token = body.access_token, !token.isEmpty else { throw CloudOCRError.token("无 access_token") }
        return token
    }

    private struct OCRBody: Decodable {
        struct Word: Decodable { let words: String? }
        let words_result: [Word]?
        let error_code: Int?
        let error_msg: String?
    }

    /// Join `words_result[].words`, one per line. A business `error_code` → throws `.api`.
    static func parseOCRResponse(_ data: Data) throws -> String {
        guard let body = try? JSONDecoder().decode(OCRBody.self, from: data) else {
            throw CloudOCRError.emptyText
        }
        if let code = body.error_code { throw CloudOCRError.api(code: code, message: body.error_msg) }
        let lines = (body.words_result ?? []).compactMap { $0.words }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
