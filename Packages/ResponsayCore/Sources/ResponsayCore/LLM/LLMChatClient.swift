import Foundation

/// Executes an OpenAI-compatible text request and returns the model's text content. It accepts
/// both Responses (`output[].content[].text`) and Chat Completions (`choices[].message.content`)
/// so the shared higher-level APIs remain provider-neutral.
/// App-direct (epic 238): the app calls the BYOK provider straight, no backend. The session
/// is injectable for headless tests (stub URLProtocol), mirroring `DirectCloudTTSEngine` (195).
struct LLMChatClient: Sendable {
    let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    /// POST a prebuilt request; return the cleaned assistant text.
    func execute(_ request: URLRequest) async throws -> String {
        let data = try await executeRaw(request)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = Self.textContent(from: obj) else {
            throw LLMError.emptyContent
        }
        let cleaned = Self.stripThink(content).trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { throw LLMError.emptyContent }
        return cleaned
    }

    /// POST a prebuilt request and return the raw provider body. Search
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

    static func textContent(from object: [String: Any]) -> String? {
        if let output = object["output"] as? [[String: Any]] {
            let text = output.compactMap { item -> String? in
                guard item["type"] as? String == "message",
                      let parts = item["content"] as? [[String: Any]] else { return nil }
                let joined = parts.compactMap { part -> String? in
                    guard part["type"] as? String == "output_text" else { return nil }
                    return part["text"] as? String
                }.joined()
                return joined.isEmpty ? nil : joined
            }.joined()
            if !text.isEmpty { return text }
        }
        guard let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else { return nil }
        return message["content"] as? String
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
