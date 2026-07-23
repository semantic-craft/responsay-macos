import Foundation

/// Executes an OpenAI-compatible chat request and returns the model's text content.
/// App-direct (epic 238): the app calls the BYOK provider straight, no backend. The session
/// is injectable for headless tests (stub URLProtocol), mirroring `DirectCloudTTSEngine` (195).
struct LLMChatClient: Sendable {
    let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    /// POST a prebuilt request; return the cleaned text content of choice 0.
    func execute(_ request: URLRequest) async throws -> String {
        let data = try await executeRaw(request)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.emptyContent
        }
        let cleaned = Self.stripThink(content).trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { throw LLMError.emptyContent }
        return cleaned
    }

    /// POST a prebuilt request and return the raw chat-completion body. Search
    /// verification needs provider-side citation/search fields in addition to content.
    func executeRaw(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LLMError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.network("无 HTTP 响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw LLMError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    /// Drop EVERY leaked `<think>…</think>` reasoning block — case-insensitive, tolerating
    /// attributes (`<think foo="bar">`). An UNCLOSED `<think>` (truncated output) is left intact
    /// rather than nuking the remainder. Mirrors openless `strip_thinking_blocks`.
    static func stripThink(_ s: String) -> String {
        var result = s
        let openPattern = #"<think(\s[^>]*)?>"#
        while let open = result.range(of: openPattern, options: [.regularExpression, .caseInsensitive]) {
            guard let close = result.range(
                of: "</think>", options: [.caseInsensitive],
                range: open.upperBound..<result.endIndex) else {
                break   // unclosed → leave the remainder as-is (openless semantics)
            }
            result.removeSubrange(open.lowerBound..<close.upperBound)
        }
        return result
    }
}
