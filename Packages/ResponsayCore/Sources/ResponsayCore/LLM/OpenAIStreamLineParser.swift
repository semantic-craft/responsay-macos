import Foundation

/// Parses one line of a provider's OpenAI-compatible streaming response into a `TextStreamEvent`.
/// App-direct streaming (245): the app reads the VENDOR's SSE frames directly (no backend re-frame),
/// decoding the OpenAI-compatible shape:
///   `data: {"choices":[{"delta":{"content":"…"}}]}`  → `.delta`
///   `data: [DONE]`                                   → `.done`
///   `data: {"error":{"message":"…"}}`                → `.failed`
/// Blank lines, `:` keep-alives, and content-free chunks (finish_reason only) are ignored. Pure.
public struct OpenAIStreamLineParser: TextStreamEventParser {
    public init() {}

    public func event(for line: String) -> TextStreamEvent? {
        // `.whitespacesAndNewlines` (not `.whitespaces`) so a trailing `\r` from CRLF framing is trimmed.
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix(":") else { return nil }
        guard trimmed.hasPrefix("data:") else { return nil }
        let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespacesAndNewlines)
        if payload == "[DONE]" { return .done }
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let error = object["error"] {
            // error may be an object ({message}) or a plain string — preserve the text either way.
            let message = (error as? [String: Any])?["message"] as? String
                ?? (error as? String) ?? "stream error"
            return .failed(message)
        }
        guard let choices = object["choices"] as? [[String: Any]], let first = choices.first else { return nil }
        if let delta = first["delta"] as? [String: Any],
           let content = delta["content"] as? String, !content.isEmpty {
            return .delta(content)
        }
        return nil   // finish_reason-only chunk; the terminal [DONE] arrives separately
    }
}
