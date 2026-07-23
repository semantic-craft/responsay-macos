import Foundation

/// Compiles a dictionary `pattern` containing `{num}` / `{letter}` / `{word}`
/// placeholders into an `NSRegularExpression`, and rebuilds a `replacement`
/// (which may reuse the same placeholders, positionally) from a match's groups.
///
/// Runs of ASCII spaces in the literal pattern become `\s*`, so ASR spacing
/// variance still matches ("第 {num} 条" ~ "第3条"). Spec §7.2.2.
struct WildcardPattern {
    enum Wildcard: String {
        case num, letter, word

        var regex: String {
            switch self {
            // Arabic, full-width, and Chinese numerals (incl. 〇/两/大写).
            case .num:
                return "([0-9０-９〇零两一二三四五六七八九十百千万亿壹贰叁肆伍陆柒捌玖拾佰仟]+)"
            case .letter:
                return "([A-Za-z])"
            case .word:
                return "([\\p{L}\\p{N}]+)"
            }
        }
    }

    enum Token: Equatable {
        case literal(String)
        case wildcard(Wildcard)
    }

    let tokens: [Token]
    let regex: NSRegularExpression

    init?(pattern: String, caseInsensitive: Bool = false) {
        let tokens = WildcardPattern.tokenize(pattern)
        var source = ""
        for token in tokens {
            switch token {
            case .literal(let text): source += WildcardPattern.escapeLiteral(text)
            case .wildcard(let wildcard): source += wildcard.regex
            }
        }
        var options: NSRegularExpression.Options = []
        if caseInsensitive { options.insert(.caseInsensitive) }
        guard let regex = try? NSRegularExpression(pattern: source, options: options) else { return nil }
        self.tokens = tokens
        self.regex = regex
    }

    /// Split a pattern/replacement into literal + wildcard tokens.
    static func tokenize(_ pattern: String) -> [Token] {
        var tokens: [Token] = []
        var literal = ""
        var index = pattern.startIndex
        while index < pattern.endIndex {
            if pattern[index] == "{",
               let close = pattern[index...].firstIndex(of: "}") {
                let name = String(pattern[pattern.index(after: index)..<close])
                if let wildcard = Wildcard(rawValue: name) {
                    if !literal.isEmpty { tokens.append(.literal(literal)); literal = "" }
                    tokens.append(.wildcard(wildcard))
                    index = pattern.index(after: close)
                    continue
                }
            }
            literal.append(pattern[index])
            index = pattern.index(after: index)
        }
        if !literal.isEmpty { tokens.append(.literal(literal)) }
        return tokens
    }

    /// Escape regex metacharacters; collapse space runs to `\s*`.
    static func escapeLiteral(_ string: String) -> String {
        var output = ""
        var pendingSpace = false
        for character in string {
            if character == " " { pendingSpace = true; continue }
            if pendingSpace { output += "\\s*"; pendingSpace = false }
            output += NSRegularExpression.escapedPattern(for: String(character))
        }
        if pendingSpace { output += "\\s*" }
        return output
    }

    /// Build the replacement for one match: the k-th wildcard token in
    /// `replacement` takes the k-th captured group (positional).
    func expand(replacement: String, match: NSTextCheckingResult, in text: String) -> String {
        var groups: [String] = []
        if match.numberOfRanges > 1 {
            for groupIndex in 1..<match.numberOfRanges {
                if let range = Range(match.range(at: groupIndex), in: text) {
                    groups.append(String(text[range]))
                } else {
                    groups.append("")
                }
            }
        }
        var output = ""
        var groupCursor = 0
        for token in WildcardPattern.tokenize(replacement) {
            switch token {
            case .literal(let text): output += text
            case .wildcard:
                output += groupCursor < groups.count ? groups[groupCursor] : ""
                groupCursor += 1
            }
        }
        return output
    }
}
