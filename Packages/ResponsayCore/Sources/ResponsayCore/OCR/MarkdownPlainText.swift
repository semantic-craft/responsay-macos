import Foundation

// MARK: - Cloud OCR · Markdown → plain text (pure function)
//
// Mistral OCR returns Markdown per page. Snap & Translate's default output is clean, pasteable
// plain text, so strip the common markup (headings / emphasis / links / lists / rules). Ported from
// the bob-plugin-mistral-ocr `stripMarkdown`. Pure (NSRegularExpression only) → unit-testable.

public enum MarkdownPlainText {

    public static func from(_ markdown: String) -> String {
        var text = markdown
        let rules: [(String, String)] = [
            (#"!\[([^\]]*)\]\([^)]*\)"#, "$1"),     // image ![alt](url) → alt
            (#"\[([^\]]*)\]\([^)]*\)"#, "$1"),      // link [text](url) → text
            (#"(?m)^\s{0,3}#{1,6}\s+"#, ""),        // heading #
            (#"\*{1,3}([^*]+)\*{1,3}"#, "$1"),      // bold/italic *
            (#"_{1,3}([^_]+)_{1,3}"#, "$1"),        // bold/italic _
            (#"~~([^~]+)~~"#, "$1"),                // strikethrough
            (#"`([^`]+)`"#, "$1"),                  // inline code
            (#"(?m)^\s*>\s+"#, ""),                 // blockquote
            (#"(?m)^\s*[-*+]\s+"#, ""),             // unordered list
            (#"(?m)^\s*\d+\.\s+"#, ""),             // ordered list
            (#"(?m)^\s*([-*_])\1{2,}\s*$"#, ""),    // horizontal rule
        ]
        for (pattern, replacement) in rules {
            text = replace(text, pattern: pattern, with: replacement)
        }
        return text
    }

    private static func replace(_ input: String, pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
        let range = NSRange(input.startIndex..., in: input)
        return regex.stringByReplacingMatches(in: input, range: range, withTemplate: template)
    }
}
