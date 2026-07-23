import Foundation

public extension ProsodyAnalysis {
    /// 125 — a minimal analysis seeded from an arbitrary English sentence, so the follow-read
    /// loop can start from selected / rewritten text (not only the canned samples). Words are
    /// rendered without inventing stress / syllable / IPA analysis; only the sentence-terminal
    /// tone is inferred. Full prosody (stress, nuclear, linking, multi-group) stays the
    /// analyzer's job (143 / backend `/analyze`); this is the honest un-analyzed seed.
    static func followReadSeed(from text: String) -> ProsodyAnalysis {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        let words = tokens.map { token in
            Word(text: token, syllables: [token], stressIndex: nil,
                 stressed: false, nuclear: false, ipa: nil, linkToNext: nil)
        }
        let groups = words.isEmpty
            ? []
            : [ThoughtGroup(tone: terminalTone(of: trimmed), words: words)]
        return ProsodyAnalysis(
            text: tokens.joined(separator: " "),
            isGeneratedExample: false,
            sourceWord: nil,
            ipa: "",
            thoughtGroups: groups,
            notes: nil)
    }

    /// Sentence-terminal intonation: a trailing `?` rises, everything else falls. Honest minimum
    /// — no clause-level tone inference (that is the analyzer's job).
    private static func terminalTone(of text: String) -> Tone {
        text.hasSuffix("?") ? .rise : .fall
    }
}
