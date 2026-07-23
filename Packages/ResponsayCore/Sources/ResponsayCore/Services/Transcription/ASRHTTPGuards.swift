import Foundation

/// The HTTP guards every cloud transcription provider repeated (#2 deepening) — audio-size,
/// status-validation, empty-result — in one place so a fix lands once and the providers become
/// thin adapters. `brand` is the provider's error prefix (e.g. "OpenAI ASR"); the user-facing
/// strings are byte-identical to the pre-extraction per-provider code.
public enum ASRHTTPGuards {
    /// Reject audio over the provider's byte cap. The "录音太长" message is shared verbatim.
    public static func audioSize(_ audio: Data, max: Int) throws {
        guard audio.count <= max else {
            throw CoachAPIError.message("录音太长，请缩短后再试。")
        }
    }

    /// Validate the HTTP response: a non-HTTP response throws "`brand` 网络错误"; a non-2xx status
    /// throws "`brand` `code`: `body`" (body truncated to 200 chars). Returns the validated response.
    @discardableResult
    public static func validate(_ response: URLResponse, data: Data, brand: String) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else {
            throw CoachAPIError.message("\(brand) 网络错误")
        }
        guard (200..<300).contains(http.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? ""
            throw CoachAPIError.message("\(brand) \(http.statusCode): \(errorText.prefix(200))")
        }
        return http
    }

    /// Reject an empty transcript with "`brand` 返回为空"; returns the text otherwise.
    @discardableResult
    public static func nonEmpty(_ text: String, brand: String) throws -> String {
        guard !text.isEmpty else {
            throw CoachAPIError.message("\(brand) 返回为空")
        }
        return text
    }
}
