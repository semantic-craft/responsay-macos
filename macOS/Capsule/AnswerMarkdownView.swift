import SwiftUI

/// Lightweight, stream-tolerant Markdown block renderer for the 任意提问 answer card
/// (design Surface 4 — H3 / paragraph / bullet / fenced-code blocks). The LLM answer
/// streams in token-by-token, so the parser must never throw on a half-written line
/// (an unterminated ``` or `**`): it falls back to plain text and tolerates an open
/// code fence by rendering the remainder as code.
///
/// This is a *rendering* job, not a full CommonMark engine — it covers the block kinds
/// the design uses and leans on `AttributedString(markdown:)` for inline bold / `code` /
/// links inside each line.
struct AnswerMarkdownView: View {
    let text: String

    private var blocks: [AnswerBlock] { AnswerMarkdownParser.parse(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            ForEach(blocks) { block in
                switch block.kind {
                case .heading:
                    Text(block.text)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(SettingsTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                case .paragraph:
                    inlineText(block.text)
                        .font(.system(size: 13.5))
                        .lineSpacing(3)
                        .foregroundStyle(SettingsTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                case .bullet:
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text(block.marker)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SettingsTheme.wine)
                        inlineText(block.text)
                            .font(.system(size: 13.5))
                            .lineSpacing(2)
                            .foregroundStyle(SettingsTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .code:
                    Text(block.text)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Color(red: 0.92, green: 0.88, blue: 0.82))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(red: 0.114, green: 0.090, blue: 0.071))
                        )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Inline markdown (bold / `code` / links) with a plain-text fallback. Uses
    /// `AttributedString(markdown:)` rather than `Text(.init(String))` so a stray `%`
    /// in the answer can't be misread as a format specifier, and a half-written marker
    /// mid-stream degrades to literal text instead of throwing.
    private func inlineText(_ string: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: string,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(string)
    }
}

// MARK: - Parser

/// One rendered block in an answer.
struct AnswerBlock: Identifiable {
    enum Kind { case heading, paragraph, bullet, code }
    let id: Int
    let kind: Kind
    let text: String
    /// Bullet glyph or "1." style ordinal; empty for non-bullets.
    var marker: String = ""
}

/// Tolerant line-based block splitter. Headings (`#…`), bullets (`-`/`*`/`1.`),
/// fenced code (```` ``` ````), and paragraphs separated by blank lines. An unterminated
/// code fence (still streaming) renders its accumulated lines as a code block.
enum AnswerMarkdownParser {
    static func parse(_ text: String) -> [AnswerBlock] {
        var blocks: [AnswerBlock] = []
        var paragraph: [String] = []
        var code: [String] = []
        var inCode = false
        var next = 0

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(AnswerBlock(id: next, kind: .paragraph,
                                      text: paragraph.joined(separator: " ")))
            next += 1
            paragraph.removeAll()
        }
        func flushCode() {
            guard !code.isEmpty else { return }
            blocks.append(AnswerBlock(id: next, kind: .code, text: code.joined(separator: "\n")))
            next += 1
            code.removeAll()
        }

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if inCode { flushCode(); inCode = false }
                else { flushParagraph(); inCode = true }
                continue
            }
            if inCode { code.append(line); continue }

            if trimmed.isEmpty { flushParagraph(); continue }

            if let heading = headingText(trimmed) {
                flushParagraph()
                blocks.append(AnswerBlock(id: next, kind: .heading, text: heading)); next += 1
                continue
            }
            if let (marker, body) = bullet(trimmed) {
                flushParagraph()
                blocks.append(AnswerBlock(id: next, kind: .bullet, text: body, marker: marker)); next += 1
                continue
            }
            paragraph.append(trimmed)
        }
        flushParagraph()
        flushCode()  // an open fence at end-of-stream still renders
        return blocks
    }

    private static func headingText(_ line: String) -> String? {
        guard line.hasPrefix("#") else { return nil }
        let stripped = line.drop(while: { $0 == "#" })
        guard stripped.first == " " else { return nil }
        return stripped.trimmingCharacters(in: .whitespaces)
    }

    /// Returns (display marker, body) for `-`, `*`, `+` and `N.` list items.
    private static func bullet(_ line: String) -> (String, String)? {
        for prefix in ["- ", "* ", "+ "] where line.hasPrefix(prefix) {
            return ("▸", String(line.dropFirst(prefix.count)))
        }
        // ordered: "12. body"
        if let dot = line.firstIndex(of: "."),
           line.distance(from: line.startIndex, to: dot) <= 3,
           line[line.startIndex..<dot].allSatisfy(\.isNumber),
           line.index(after: dot) < line.endIndex,
           line[line.index(after: dot)] == " " {
            let ordinal = String(line[line.startIndex...dot])
            let body = String(line[line.index(dot, offsetBy: 2)...])
            return (ordinal, body)
        }
        return nil
    }
}
