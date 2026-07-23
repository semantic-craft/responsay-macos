import Foundation

/// Retrieval gate for the optional BYOK-LLM correction tier (#500 S3, RAG-NER per Apple
/// arxiv 2409.06062). Finds user hotwords that are **phonetically near** a span of the (already
/// hard-matched) transcript but are NOT exactly present — i.e. the near-misses the #465 pass could
/// not snap (non-confusable drift like 茨↔兹, below budget, polyphone-blocked). These become the
/// small term list handed to the LLM. Empty result ⇒ the caller skips the LLM entirely, so the tier
/// costs nothing on the common case.
///
/// Syllable-aligned, not raw string distance (review hardening): the window width is the term's
/// **syllable** count (so a term with an embedded dot/space like 卡尔·拉伦茨 still aligns with the
/// contiguous ASR span), and each window is compared syllable-by-syllable — a differing syllable
/// only counts as a near-miss if it shares an initial OR final (catches 茨/兹, rejects unrelated
/// syllables that a boundary-free Levenshtein would bridge). Restricted to ≥3-syllable CJK terms:
/// 2-syllable terms collide coincidentally across word boundaries (盘一≈判例), and the confusable
/// 2-char cases are already the hard-match's job.
public enum HotwordCorrectionCandidates {

    /// Cap on the candidate list handed to the LLM (#516) — keeps the prompt small and the
    /// correction focused even when many dictionary terms are phonetically close to one span.
    static let maxCandidates = 5

    /// User terms with a plausible phonetic near-miss in `text` (CJK: syllable-aligned within a
    /// small per-syllable diff budget; Latin (#516): consonant-skeleton match over sliding word
    /// windows) that are not already present verbatim. De-duplicated, original order, ≤5.
    public static func nearMiss(in text: String, userTerms: [String], maxSyllableDiff: Int = 2) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !userTerms.isEmpty else { return [] }

        // One toneless syllable per character ("" for non-CJK), so a window is a slice of these.
        let perChar = Array(text).map { HotwordHardMatch.pinyinSyllables(String($0)).joined() }
        let asciiWords = asciiWordKeys(text)

        var out: [String] = []
        var seen = Set<String>()
        for raw in userTerms {
            let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !seen.contains(term), !text.contains(term) else { continue }
            let termSylls = HotwordHardMatch.pinyinSyllables(term)
            let isCandidate: Bool
            if termSylls.count >= 3 {
                let budget = min(maxSyllableDiff, max(1, termSylls.count / 3))
                isCandidate = isPhoneticallyNear(termSylls: termSylls, perChar: perChar, maxDiff: budget)
            } else {
                // 516 — Latin terms have no pinyin syllables; match on the consonant skeleton instead.
                isCandidate = isASCIINearMiss(term: term, words: asciiWords)
            }
            if isCandidate {
                seen.insert(term)
                out.append(term)
                if out.count == maxCandidates { break }
            }
        }
        return out
    }

    /// 516 — English/Latin retrieval: does some 1…(term words + 1) sliding window of the
    /// transcript's ASCII words sound like `term`? Compared in `HotwordHardMatch.phoneticKey`
    /// consonant-skeleton space with a recall-first budget (this tier is advisory — the LLM and
    /// `HotwordCorrectionGuard` keep precision downstream, unlike the deterministic hard-match):
    /// skeleton edit distance ≤ half the term skeleton, or a shared ≥4-consonant prefix (catches
    /// run-together mishears like Metapocalypse ↔ Matt Pocock).
    private static func isASCIINearMiss(term: String, words: [String]) -> Bool {
        let termKey = HotwordHardMatch.normalizeKey(term)
        guard termKey.count >= 4, !words.isEmpty else { return false }
        let termPhone = HotwordHardMatch.phoneticKey(termKey)
        guard termPhone.count >= 2 else { return false }
        let termWordCount = max(1, term.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).count)
        let budget = max(1, termPhone.count / 2)
        for width in 1...(termWordCount + 1) where width <= words.count {
            for start in 0...(words.count - width) {
                let windowPhone = HotwordHardMatch.phoneticKey(words[start..<start + width].joined())
                guard windowPhone.count >= max(2, termPhone.count - 1) else { continue }
                if HotwordHardMatch.levenshtein(windowPhone, termPhone) <= budget { return true }
                if min(windowPhone.count, termPhone.count) >= 4,
                   windowPhone.hasPrefix(termPhone) || termPhone.hasPrefix(windowPhone) {
                    return true
                }
            }
        }
        return false
    }

    /// The transcript's ASCII words, normalized to lowercase `[a-z0-9]` keys, in order.
    private static func asciiWordKeys(_ text: String) -> [String] {
        var words: [String] = []
        var current = ""
        for character in text {
            if let ascii = character.asciiValue,
               (48...57).contains(ascii) || (65...90).contains(ascii) || (97...122).contains(ascii) {
                current.append(character)
            } else if !current.isEmpty {
                words.append(HotwordHardMatch.normalizeKey(current))
                current = ""
            }
        }
        if !current.isEmpty { words.append(HotwordHardMatch.normalizeKey(current)) }
        return words
    }

    /// True when some contiguous CJK window of `perChar` (width = `termSylls.count`) is a per-syllable
    /// near-miss of the term. The window must be all-CJK (no empty syllable), so it never straddles
    /// punctuation or Latin.
    private static func isPhoneticallyNear(termSylls: [String], perChar: [String], maxDiff: Int) -> Bool {
        let width = termSylls.count
        guard width >= 1, perChar.count >= width else { return false }
        var start = 0
        while start + width <= perChar.count {
            let window = Array(perChar[start..<start + width])
            if window.allSatisfy({ !$0.isEmpty }), syllablesNearMiss(window, termSylls, maxDiff: maxDiff) {
                return true
            }
            start += 1
        }
        return false
    }

    /// Same-length syllable sequences that differ in 1…`maxDiff` syllables, where each differing
    /// syllable still shares an initial OR a final (a genuine near-miss, not an unrelated syllable).
    private static func syllablesNearMiss(_ a: [String], _ b: [String], maxDiff: Int) -> Bool {
        guard a.count == b.count else { return false }
        var diff = 0
        for (x, y) in zip(a, b) where x != y {
            let (ix, fx) = HotwordHardMatch.splitSyllable(x)
            let (iy, fy) = HotwordHardMatch.splitSyllable(y)
            guard ix == iy || fx == fy else { return false }
            diff += 1
            if diff > maxDiff { return false }
        }
        return diff >= 1
    }
}
