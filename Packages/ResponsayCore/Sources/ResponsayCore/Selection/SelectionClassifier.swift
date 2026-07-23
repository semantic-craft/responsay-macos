import Foundation

/// A cheap, **rules-first** selection classifier — no model round-trip, mirroring
/// the legal scene router's rules-before-model stance (issue 126 / ADR-0022).
///
/// It answers one question for the action menu: is this selection a Latin,
/// sentence-shaped piece of English we can offer oral practice on?
public struct SelectionClassifier: Sendable {
    /// Minimum Latin word count for a selection to read as a sentence (not a
    /// 1–2 word fragment like "Thank you").
    public static let sentenceWordThreshold = 3

    public init() {}

    public func classify(_ text: String) -> SelectionClassification {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        var latinLetters = 0
        var hanChars = 0
        for scalar in trimmed.unicodeScalars {
            if Self.isHan(scalar) {
                hanChars += 1
            } else if Self.isLatin(scalar) {
                latinLetters += 1
            }
        }

        let script = Self.script(latinLetters: latinLetters, hanChars: hanChars)
        let latinWordCount = trimmed
            .split(whereSeparator: \.isWhitespace)
            .reduce(into: 0) { count, token in
                if token.unicodeScalars.contains(where: Self.isLatin) { count += 1 }
            }
        let isSentenceShaped = latinWordCount >= Self.sentenceWordThreshold
        let eligible = script == .latin && isSentenceShaped

        return SelectionClassification(
            script: script,
            latinWordCount: latinWordCount,
            isSentenceShaped: isSentenceShaped,
            isEnglishPracticeEligible: eligible
        )
    }

    // MARK: - Script heuristics

    private static func script(latinLetters: Int, hanChars: Int) -> SelectionClassification.Script {
        let total = latinLetters + hanChars
        guard total > 0 else { return .other }
        let latinFraction = Double(latinLetters) / Double(total)
        if latinFraction >= 0.6 { return .latin }
        if latinFraction <= 0.4 { return .han }
        return .mixed
    }

    private static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        return (0x4E00...0x9FFF).contains(value)   // CJK Unified Ideographs
            || (0x3400...0x4DBF).contains(value)   // Extension A
            || (0xF900...0xFAFF).contains(value)   // Compatibility Ideographs
            || (0x20000...0x2A6DF).contains(value) // Extension B
    }

    private static func isLatin(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        let inLatinBlock = (0x41...0x5A).contains(value)   // A–Z
            || (0x61...0x7A).contains(value)               // a–z
            || (0x00C0...0x024F).contains(value)           // Latin-1 Supp + Extended-A/B
        return inLatinBlock && scalar.properties.isAlphabetic
    }
}
