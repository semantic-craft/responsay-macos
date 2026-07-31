import Foundation

/// Tolerant extraction of the model's JSON payload from a chat completion's text content.
/// The App-direct prompts ask for "exactly one JSON object as raw text", but models still
/// occasionally wrap it in a ```json fence or add stray prose; we strip fences and slice the
/// outermost {…}. Mirrors the spirit of backend `cleanModelOutput` + the coach decoders.
enum LLMResponseParsing {
    /// The outermost {…} of the content, with a ```json fence stripped. Shared by the
    /// `[String: Any]` and `Data` (Codable) decode paths.
    static func slicedJSON(from raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            if let firstNewline = s.firstIndex(of: "\n") { s = String(s[s.index(after: firstNewline)...]) }
            if let fence = s.range(of: "```", options: .backwards) { s = String(s[..<fence.lowerBound]) }
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let start = s.firstIndex(of: "{") else { return nil }
        // Balanced, string-aware scan to the object's own closing brace: models
        // occasionally append a stray `}` or prose after the object (live eval
        // 2026-07-31: qwen3.7-flash intent plans, ~2/4), and a first-{…last-} slice
        // folds that junk into the payload, sinking strict decoding downstream.
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < s.endIndex {
            let ch = s[index]
            if inString {
                if escaped { escaped = false }
                else if ch == "\\" { escaped = true }
                else if ch == "\"" { inString = false }
            } else {
                switch ch {
                case "\"": inString = true
                case "{": depth += 1
                case "}":
                    depth -= 1
                    if depth == 0 { return String(s[start...index]) }
                default: break
                }
            }
            index = s.index(after: index)
        }
        // Never balances (truncated payload): keep the legacy first-{…last-} slice so
        // that class of input behaves exactly as before.
        guard let end = s.lastIndex(of: "}"), start < end else { return nil }
        return String(s[start...end])
    }

    static func jsonObject(from raw: String) -> [String: Any]? {
        guard let slice = slicedJSON(from: raw),
              let data = slice.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj
    }

    /// The sliced JSON as `Data`, for decoding into a `Codable` (e.g. `ProsodyAnalysis`).
    static func jsonData(from raw: String) -> Data? {
        slicedJSON(from: raw)?.data(using: .utf8)
    }

    static func string(_ obj: [String: Any], _ key: String) -> String {
        (obj[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static func stringArray(_ obj: [String: Any], _ key: String) -> [String] {
        guard let raw = obj[key] as? [Any] else { return [] }
        return raw.compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
