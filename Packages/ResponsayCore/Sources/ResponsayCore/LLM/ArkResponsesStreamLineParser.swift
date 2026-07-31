import Foundation

/// Parses one line of an OpenAI-compatible **Responses API** SSE stream into a `TextStreamEvent`.
///
/// Qwen and Doubao web-search streams use the OpenAI *Responses* event shape (not the chat
/// `choices[].delta` shape):
///   `data: {"type":"response.output_text.delta","delta":"…"}`  → `.delta`
///   `data: {"type":"response.completed", …}`                   → `.done`
///   `data: {"type":"response.failed","response":{"error":{"message":"…"}}}` → `.failed`
///   `data: [DONE]`                                             → `.done`
///
/// Providers may frame each event as an `event: <type>` line followed by a `data: <json>` line;
/// the JSON itself carries `type`, so we only read `data:` lines. Reasoning/output-item/content-part
/// scaffolding events are ignored (return nil) — only text deltas and the terminal matter. Pure.
public struct ArkResponsesStreamLineParser: TextStreamEventParser {
    public init() {}

    public func event(for line: String) -> TextStreamEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix(":") else { return nil }
        guard trimmed.hasPrefix("data:") else { return nil }
        let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespacesAndNewlines)
        if payload == "[DONE]" { return .done }
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else {
            return nil
        }
        switch type {
        case "response.output_text.delta":
            if let delta = object["delta"] as? String, !delta.isEmpty { return .delta(delta) }
            return nil
        case "response.completed", "response.incomplete":
            return .done
        case "response.failed", "error":
            return .failed(errorMessage(object) ?? "stream error")
        default:
            return nil
        }
    }

    /// `response.failed` nests the error under `response.error.message`; a bare `error` event may
    /// carry it at the top level as an object or a plain string.
    private func errorMessage(_ object: [String: Any]) -> String? {
        if let response = object["response"] as? [String: Any],
           let error = response["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        return object["error"] as? String
    }
}
