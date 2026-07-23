import Foundation

public struct RuleBasedHotwordCandidateExtractor: HotwordCandidateExtracting {
    public init() {}

    public func extract(_ context: HotwordCorrectionContext) async throws -> [HotwordCandidateProposal] {
        let delta = EditDelta.compute(inserted: context.insertedText, userFinal: context.userFinalText)
        guard !delta.isLargeModify || delta.substitutions.count == 1 else { return [] }

        return delta.substitutions.compactMap { substitution in
            let source = Self.cleanCandidate(substitution.from)
            let term = Self.cleanCandidate(substitution.to)
            let expanded = Self.expandedCapitalizedPhrase(
                source: source,
                term: term,
                insertedText: context.insertedText,
                finalText: context.userFinalText)
            let learnedSource = expanded?.source ?? source
            let learnedTerm = expanded?.term ?? term
            if Self.asciiKey(learnedSource) == Self.asciiKey(learnedTerm),
               Self.hasBoundarySentencePunctuation(in: substitution.to) {
                return nil
            }
            guard Self.isLearnable(learnedTerm),
                  Self.looksLikeASRCorrection(from: learnedSource, to: learnedTerm) else { return nil }
            return HotwordCandidateProposal(
                term: learnedTerm,
                source: .localRules,
                confidence: Self.confidence(from: learnedSource, to: learnedTerm),
                reason: "用户把「\(learnedSource)」改成「\(learnedTerm)」",
                sourceTerm: learnedSource,
                appName: context.appName,
                windowTitle: context.windowTitle)
        }
    }

    private static func isLearnable(_ term: String) -> Bool {
        term.count >= 2
            && term.count <= 40
            && !hasInteriorSentenceBoundary(in: term)
    }

    /// How confident we are this correction is a term worth auto-adding. A plain everyday ASCII word
    /// is only a *candidate* at confirm-band confidence — the user approves it before it biases
    /// recognition, so a one-off mis-hearing can't silently pollute the dictionary. Distinctive terms
    /// (digits/hyphen/interior caps/merged proper name) and pure-CJK terms keep the auto-add band.
    private static func confidence(from: String, to: String) -> Double {
        isPlainWord(from: from, to: to) ? 0.70 : 0.86
    }

    /// A plain everyday ASCII word: it has an ASCII form but none of the distinctive shapes.
    /// Pure-CJK terms (no ASCII form) are NOT plain — they keep the original auto-add behavior.
    private static func isPlainWord(from: String, to: String) -> Bool {
        !asciiKey(to).isEmpty && !isShaped(from: from, to: to)
    }

    /// A "distinctive" correction target: a proper-noun/brand/code-like shape, or two ordinary words
    /// the ASR ran together into one capitalized name. Plain everyday words are NOT shaped.
    private static func isShaped(from: String, to: String) -> Bool {
        hasHotwordShape(to) || looksLikeMergedProperName(from: from, to: to)
    }

    private static func looksLikeASRCorrection(from: String, to: String) -> Bool {
        let fromKey = asciiKey(from)
        let toKey = asciiKey(to)
        if fromKey == toKey, !fromKey.isEmpty, hasBoundarySentencePunctuation(in: to) {
            return false
        }
        if !fromKey.isEmpty || !toKey.isEmpty {
            guard !looksLikeCommandPhrase(fromKey) else { return false }
            let budget = maxDistance(forLength: toKey.count)
            if abs(fromKey.count - toKey.count) <= budget,
               levenshtein(Array(fromKey), Array(toKey)) <= budget {
                return true
            }
            let fromPhone = HotwordHardMatch.phoneticKey(fromKey)
            let toPhone = HotwordHardMatch.phoneticKey(toKey)
            guard !fromPhone.isEmpty, !toPhone.isEmpty else { return false }
            // Distinctive terms (proper names/brands) can be heard quite differently, so they keep a
            // fuzzy phonetic budget. A plain everyday word must match phonetically EXACTLY — that's
            // what separates a deliberate respelling (cloud→Claude) from a typing fragment
            // (Cloud→Clou) or a loose slip, which would otherwise be learned as junk.
            if isShaped(from: from, to: to) {
                let phoneBudget = max(1, min(2, toPhone.count / 2))
                return abs(fromPhone.count - toPhone.count) <= phoneBudget
                    && levenshtein(Array(fromPhone), Array(toPhone)) <= phoneBudget
            }
            return fromPhone == toPhone
        }

        let length = max(from.count, to.count)
        let budget = length <= 2 ? 0 : 1
        return levenshtein(Array(from), Array(to)) <= budget
    }

    private static let boundarySentencePunctuation = CharacterSet(charactersIn: ".,;:!?，。；：！？")

    private static func hasBoundarySentencePunctuation(in value: String) -> Bool {
        guard let first = value.unicodeScalars.first,
              let last = value.unicodeScalars.last else { return false }
        return boundarySentencePunctuation.contains(first)
            || boundarySentencePunctuation.contains(last)
    }

    private static func hasInteriorSentenceBoundary(in value: String) -> Bool {
        let scalars = Array(value.unicodeScalars)
        guard scalars.count > 2 else { return false }
        return scalars.dropFirst().dropLast().contains {
            boundarySentencePunctuation.contains($0)
        }
    }

    private static func asciiKey(_ value: String) -> String {
        var out = ""
        for character in value {
            guard let ascii = character.asciiValue else { continue }
            switch ascii {
            case 48...57, 97...122:
                out.unicodeScalars.append(UnicodeScalar(ascii))
            case 65...90:
                out.unicodeScalars.append(UnicodeScalar(ascii + 32))
            default:
                continue
            }
        }
        return out
    }

    private static func hasHotwordShape(_ value: String) -> Bool {
        let words = value.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if words.count >= 2, words.allSatisfy({ isCapitalizedASCIIWord(String($0)) }) { return true }
        return value.contains { $0.isNumber }
            || value.contains("-")
            || value.contains { character in
                guard let ascii = character.asciiValue else { return false }
                return ascii >= 65 && ascii <= 90 && character != value.first
            }
    }

    private static func isCapitalizedASCIIWord(_ word: String) -> Bool {
        guard let first = word.first?.asciiValue, first >= 65, first <= 90 else { return false }
        return word.dropFirst().contains { character in
            guard let ascii = character.asciiValue else { return false }
            return ascii >= 97 && ascii <= 122
        }
    }

    private static func looksLikeMergedProperName(from: String, to: String) -> Bool {
        from.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).count >= 2
            && to.count >= 6
            && isCapitalizedASCIIWord(to)
    }

    private static func expandedCapitalizedPhrase(
        source: String,
        term: String,
        insertedText: String,
        finalText: String
    ) -> (source: String, term: String)? {
        guard isCapitalizedASCIIWord(source),
              let phrase = capitalizedPhrase(containing: term, in: finalText) else { return nil }
        let sourceTokens = phrase.map { $0 == term ? source : $0 }
        guard sourceTokens != phrase,
              contains(sourceTokens, in: EditDelta.tokenize(insertedText)) else { return nil }
        return (sourceTokens.joined(separator: " "), phrase.joined(separator: " "))
    }

    private static func capitalizedPhrase(containing term: String, in text: String) -> [String]? {
        let tokens = EditDelta.tokenize(text)
        guard let index = tokens.firstIndex(of: term), isCapitalizedASCIIWord(term) else { return nil }
        var start = index
        while start > tokens.startIndex, isCapitalizedASCIIWord(tokens[tokens.index(before: start)]) {
            start = tokens.index(before: start)
        }
        var end = tokens.index(after: index)
        while end < tokens.endIndex, isCapitalizedASCIIWord(tokens[end]) {
            end = tokens.index(after: end)
        }
        guard tokens.distance(from: start, to: end) >= 2 else { return nil }
        return Array(tokens[start..<end])
    }

    private static func contains(_ needle: [String], in haystack: [String]) -> Bool {
        guard !needle.isEmpty, needle.count <= haystack.count else { return false }
        for start in 0...(haystack.count - needle.count) where Array(haystack[start..<(start + needle.count)]) == needle {
            return true
        }
        return false
    }

    private static func looksLikeCommandPhrase(_ key: String) -> Bool {
        [
            "createnote", "makenote", "newnote", "opennote", "deletenote",
            "startnote", "savenote", "sendnote"
        ].contains(key)
    }

    private static func cleanCandidate(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines.union(boundarySentencePunctuation))
    }

    private static func maxDistance(forLength length: Int) -> Int {
        switch length {
        case ...4: return 0
        case ...8: return 1
        case ...12: return 2
        default: return 3
        }
    }

    private static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        if a == b { return 0 }
        var row = Array(0...b.count)
        for i in 1...max(a.count, 1) where !a.isEmpty {
            var previous = row[0]
            row[0] = i
            for j in 1...b.count {
                let temp = row[j]
                row[j] = a[i - 1] == b[j - 1]
                    ? previous
                    : Swift.min(previous + 1, row[j] + 1, row[j - 1] + 1)
                previous = temp
            }
        }
        return row[b.count]
    }
}
