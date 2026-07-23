import Foundation

// Untrusted-text envelope + prompt-tag escaping for TextTransformPromptAssembler. Split out to
// keep the assembler ≤400 lines; same enum namespace, so the section builders call these
// unqualified. `internal` (not `private`) only so they can live in this file.
extension TextTransformPromptAssembler {

    static func envelope(_ input: InputEnvelope, text: String, maxCharacters: Int) -> String {
        let tag = input.rawValue
        return [
            "<\(tag)>",
            truncateAndEscape(text, maxCharacters: maxCharacters),
            "</\(tag)>",
        ].joined(separator: "\n")
    }

    static func truncateAndEscape(_ text: String, maxCharacters: Int) -> String {
        let limited: String
        if maxCharacters > 0, text.count > maxCharacters {
            let dropped = text.count - maxCharacters
            limited = String(text.prefix(maxCharacters)) + "\n[truncated \(dropped) characters]"
        } else {
            limited = text
        }
        return escapePromptTags(limited)
    }

    static func escapePromptTags(_ text: String) -> String {
        protectedPromptTags.reduce(text) { current, tag in
            return current
                .replacingOccurrences(of: "</\(tag)>", with: "&lt;/\(tag)&gt;")
                .replacingOccurrences(of: "<\(tag)>", with: "&lt;\(tag)&gt;")
        }
    }

    static let protectedPromptTags = InputEnvelope.allCases.map(\.rawValue) + [
        "context_documents",
        "rewrite_context",
        "hotwords",
        "front_app",
        "prior_turn",
        "polished_text",
    ]

    static func attribute(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
