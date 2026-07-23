import Foundation

/// 517 — 屏幕专名采集: pulls candidate proper-noun terms out of the visible screen text
/// (`VisibleTextCollector`'s output) so they can bias THIS capture's ASR as transient
/// weak-prompt terms — never persisted, never into the dictionary/vocabulary/hard-match.
///
/// v1 is ASCII-only (the pain point is English proper names); extraction is shape-based:
/// 1. capitalized phrases (`Matt Pocock`) — the strongest person/brand signal, emitted first;
/// 2. shaped single tokens — digits, or interior uppercase, or hyphen-with-uppercase
///    (`Qwen3-ASR`, `DeepSeek`);
/// 3. repeated plain capitalized words (`Typeless` ×2) — a word that only ever appears
///    capitalized AND appears at least twice is a name, while a sentence-starter (`The`, `We`)
///    also shows up lowercase somewhere and is dropped without needing a stopword list.
/// ponytail: CJK 专名、apostrophe names (O'Brien)、全小写连字符词 (sherpa-onnx) 是已知天花板 —
/// 需要时给 tokenizer/shape 各加一条分支即可。
public enum ScreenTermHarvester {
    public static let maxTerms = 12
    static let maxTermLength = 80
    /// Runs of >4 consecutive capitalized words are Title Case headings/menu chrome, not names.
    static let maxPhraseWords = 4

    public static func harvest(_ screenText: String, excluding existingTerms: [String] = []) -> [String] {
        let chunks = tokenChunks(screenText)
        let allTokens = chunks.flatMap { $0 }
        let lowercaseForms = Set(allTokens.filter { $0 == $0.lowercased() })
        var counts: [String: Int] = [:]
        for token in allTokens { counts[token, default: 0] += 1 }

        var phrases: [String] = []
        var phraseWords = Set<String>()
        var singles: [String] = []
        for chunk in chunks {
            var index = 0
            while index < chunk.count {
                guard isCapitalizedWord(chunk[index]) else {
                    singles.append(chunk[index])
                    index += 1
                    continue
                }
                var end = index
                while end + 1 < chunk.count, isCapitalizedWord(chunk[end + 1]) { end += 1 }
                let run = Array(chunk[index...end])
                if run.count == 1 {
                    singles.append(run[0])
                } else {
                    // Consume every word of any multi-word run (even a discarded heading), so
                    // heading/phrase words never leak back out as single terms.
                    run.forEach { phraseWords.insert($0) }
                    if run.count <= maxPhraseWords {
                        phrases.append(run.joined(separator: " "))
                    }
                }
                index = end + 1
            }
        }

        var shaped: [String] = []
        var repeated: [String] = []
        for token in singles {
            guard !phraseWords.contains(token),
                  token.count >= 2, token.count <= maxTermLength,
                  token.contains(where: \.isLetter),
                  token.contains(where: \.isLowercase)   // ALL-CAPS = UI chrome / bare acronym
            else { continue }
            let hasUppercase = token.contains(where: \.isUppercase)
            if token.contains(where: \.isNumber)
                || hasInteriorUppercase(token)
                || (token.contains("-") && hasUppercase) {
                shaped.append(token)
            } else if isCapitalizedWord(token),
                      counts[token, default: 0] >= 2,
                      !lowercaseForms.contains(token.lowercased()) {
                repeated.append(token)
            }
        }

        let excluded = Set(existingTerms.map { $0.lowercased() })
        var seen = Set<String>()
        var output: [String] = []
        for term in phrases + shaped + repeated {
            guard term.count <= maxTermLength,
                  !excluded.contains(term.lowercased()),
                  seen.insert(term).inserted else { continue }
            output.append(term)
            if output.count == maxTerms { break }
        }
        return output
    }

    /// Chunks of space-separated ASCII tokens; ANY non-token, non-space character (punctuation,
    /// newline, CJK, …) closes the chunk, so capitalized runs never straddle a sentence boundary.
    private static func tokenChunks(_ text: String) -> [[String]] {
        var chunks: [[String]] = []
        var chunk: [String] = []
        var token = ""
        func closeToken() {
            let trimmed = token.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            if !trimmed.isEmpty { chunk.append(trimmed) }
            token = ""
        }
        func closeChunk() {
            closeToken()
            if !chunk.isEmpty { chunks.append(chunk) }
            chunk = []
        }
        for character in text {
            if let ascii = character.asciiValue,
               (48...57).contains(ascii) || (65...90).contains(ascii)
                || (97...122).contains(ascii) || ascii == 45 {
                token.append(character)
            } else if character == " " {
                closeToken()
            } else {
                closeChunk()
            }
        }
        closeChunk()
        return chunks
    }

    /// First character A–Z and at least one lowercase letter — same semantics as
    /// `RuleBasedHotwordCandidateExtractor.isCapitalizedASCIIWord` (private there).
    private static func isCapitalizedWord(_ word: String) -> Bool {
        guard let first = word.first?.asciiValue, (65...90).contains(first) else { return false }
        return word.contains(where: \.isLowercase)
    }

    private static func hasInteriorUppercase(_ word: String) -> Bool {
        word.dropFirst().contains { character in
            guard let ascii = character.asciiValue else { return false }
            return (65...90).contains(ascii)
        }
    }
}
