import Foundation

/// Result of the rules-first selection classifier (issue 126 / ADR-0022).
/// Drives the selection action menu (127): only an English, sentence-shaped
/// selection surfaces the oral-practice ("进跟读") entry.
public struct SelectionClassification: Sendable, Equatable {
    /// Dominant script of the letter-bearing characters.
    public enum Script: String, Sendable, Equatable {
        case latin      // predominantly A–Z / Latin-script letters
        case han        // predominantly 汉字
        case mixed      // a real blend of both
        case other      // no letters (digits / punctuation / symbols only)
    }

    public let script: Script
    /// Whitespace-separated tokens that carry a Latin letter.
    public let latinWordCount: Int
    /// `true` when the selection reads like a clause, not a 1–2 word fragment.
    public let isSentenceShaped: Bool
    /// Latin-dominant **and** sentence-shaped — the only state that offers
    /// English oral practice. Chinese text and short fragments are `false`.
    public let isEnglishPracticeEligible: Bool

    public init(
        script: Script,
        latinWordCount: Int,
        isSentenceShaped: Bool,
        isEnglishPracticeEligible: Bool
    ) {
        self.script = script
        self.latinWordCount = latinWordCount
        self.isSentenceShaped = isSentenceShaped
        self.isEnglishPracticeEligible = isEnglishPracticeEligible
    }
}
