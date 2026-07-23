import Foundation

/// Deterministic 口述释字 extractor (#562, homophone derivation #570). A clue phrase 「X的Y」
/// counts when the carrier word X proves the clued character Y verbatim (如何的何 — 何 ∈ 如何),
/// or — in the announced phrasing 「Y是X的Y」 only — when exactly one character of X is
/// pronounced like Y, which is then the intended character (振是城镇的振 → 镇): ASR routinely
/// renders the isolated Y as a homophone, the very mishearing the user is spelling against.
/// The phrase stays self-evidencing, which is what separates orthographic clues from ordinary
/// possessive 的 phrases with zero hardcoded names. A *clue unit* is a source unit consisting
/// solely of such phrases plus separators; consecutive clue units merge into one name.
/// Radical-decomposition conventions (弓长张 / 木子李) and English letter spelling are out of
/// scope for v1 (#526).
///
/// This is a whitelist candidate SOURCE — it renders nothing and inserts nothing. Its output
/// feeds the entity candidate table; the plan verifier and source renderer stay the only
/// authorities over the final text.
public enum IntentSpokenClueExtractor {
    /// 「X的Y」 with X = 1–6 Han chars, Y = one Han char followed by a clause boundary.
    private static let cluePattern =
        #"([\p{Script=Han}]{1,6})的([\p{Script=Han}])(?=[、，,。.！!？?；;：:\s]|$)"#
    private static let fillerCharacters = CharacterSet(charactersIn: "、，,。.！!？?；;：:")
        .union(.whitespacesAndNewlines)

    public static func extract(
        transcript: String,
        units: [IntentSourceUnit]
    ) -> [IntentSpokenClueExtraction] {
        var clueCharsByIndex = [Int: [Character]]()
        for (index, unit) in units.enumerated() {
            if let chars = clueCharacters(in: unit.originalText) {
                clueCharsByIndex[index] = chars
            }
        }
        guard !clueCharsByIndex.isEmpty else { return [] }

        var extractions = [IntentSpokenClueExtraction]()
        var group = [Int]()
        func flush() {
            guard let first = group.first else { return }
            let value = String(group.flatMap { clueCharsByIndex[$0] ?? [] })
            extractions.append(IntentSpokenClueExtraction(
                value: value,
                clueSourceIDs: group.map { units[$0].id },
                target: findTarget(
                    value: value, beforeUnitAt: first,
                    units: units, clueCharsByIndex: clueCharsByIndex)))
            group = []
        }
        for index in clueCharsByIndex.keys.sorted() {
            if let last = group.last, index != last + 1 { flush() }
            group.append(index)
        }
        flush()
        return extractions
    }

    /// Whether a whole unit is a clue unit — returns the clued characters, or nil when the unit
    /// carries any substantial non-clue content (then it is ordinary speech, not grounding).
    static func clueCharacters(in text: String) -> [Character]? {
        guard let regex = try? NSRegularExpression(pattern: cluePattern) else { return nil }
        let ns = text as NSString
        var chars = [Character]()
        var covered = IndexSet()
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let word = ns.substring(with: match.range(at: 1))
            let clued = ns.substring(with: match.range(at: 2))
            guard let character = resolvedClueCharacter(inCarrier: word, clued: clued) else { continue }
            chars.append(character)
            covered.insert(integersIn: Range(match.range)!)
        }
        guard !chars.isEmpty else { return nil }
        for position in 0..<ns.length where !covered.contains(position) {
            let leftover = ns.substring(with: NSRange(location: position, length: 1))
            guard let scalar = leftover.unicodeScalars.first, leftover.unicodeScalars.count == 1,
                  fillerCharacters.contains(scalar)
            else { return nil }   // any non-filler leftover (incl. split surrogates) → not a clue unit
        }
        return chars
    }

    /// The clue character the carrier word proves, or nil when it proves nothing (the phrase is
    /// then ordinary speech).
    ///
    /// Homophone derivation is gated on the announced phrasing 「Y是X的Y」, recognized inside the
    /// greedy capture (振是城镇的振 → word=振是城镇) by its signature: the character right before
    /// the last 是 echoes the clued character *phonetically* (either side may carry the
    /// mishearing). Only then does the 是-suffix become the sole carrier, resolved on its own —
    /// verbatim containment first, else a UNIQUE homophone derives the intended character
    /// (城镇 + 振 → 镇); ambiguity abstains. The misheard char can never prove itself via its
    /// own announcement, and ordinary 这是/就是 clauses (这是他们的门) never qualify.
    ///
    /// A plain 「X的Y」 keeps the verbatim #562 rule with no derivation: possessive phrases
    /// (他们的门, where 门/们 rhyme) must stay ordinary speech. Non-announced homophone clues
    /// (王镇，城镇的振) are a deliberate scope cut — the announced form covers real usage, and
    /// widening it re-opens the possessive false-positive class.
    static func resolvedClueCharacter(inCarrier word: String, clued: String) -> Character? {
        if let mark = word.range(of: "是", options: .backwards),
           !word[mark.upperBound...].isEmpty,
           let announced = word[..<mark.lowerBound].last,
           isHomophone(String(announced), clued) {
            let carrier = String(word[mark.upperBound...])
            if carrier.contains(clued) { return clued.first }
            let derived = carrier.filter { isHomophone(String($0), clued) }
            return derived.count == 1 ? derived.first : nil
        }
        return word.contains(clued) ? clued.first : nil
    }

    /// Tone-insensitive equality of default Mandarin readings (ICU Han-Latin + Latin-ASCII,
    /// zero dependencies). Polyphonic characters transliterate to their most common reading
    /// only — a mismatch degrades the phrase to ordinary speech, never to a wrong character.
    private static func isHomophone(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        guard let pa = pinyin(a), let pb = pinyin(b) else { return false }
        return pa == pb
    }

    private static func pinyin(_ text: String) -> String? {
        guard let latin = text.applyingTransform(
            StringTransform(rawValue: "Han-Latin; Latin-ASCII"), reverse: false) else { return nil }
        let trimmed = latin.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The unique span the assembled value replaces: same Han length, position-wise
    /// character-or-homophone overlap ≥ 1 (identity included), searched in the nearest
    /// preceding non-clue unit. Homophones count because ASR can miswrite EVERY character
    /// of a name (#571 real-Mac case: 何振杰 → 和郑姐, zero verbatim overlap with 何镇结 —
    /// yet 和~何 and 姐~结 are the same syllable, which is the whole reason the user is
    /// spelling it out). Several distinct qualifying spellings → nil (ambiguous; abstain).
    private static func findTarget(
        value: String,
        beforeUnitAt firstClueIndex: Int,
        units: [IntentSourceUnit],
        clueCharsByIndex: [Int: [Character]]
    ) -> IntentPlanSourceReference? {
        let valueChars = Array(value)
        guard !valueChars.isEmpty else { return nil }
        var index = firstClueIndex - 1
        while index >= 0, clueCharsByIndex[index] != nil { index -= 1 }
        guard index >= 0 else { return nil }
        let unit = units[index]

        let characters = Array(unit.originalText)
        var utf16Offsets = [Int]()
        var runningOffset = 0
        for character in characters {
            utf16Offsets.append(runningOffset)
            runningOffset += String(character).utf16.count
        }

        var qualifying = [(location: Int, length: Int, text: String)]()
        let n = valueChars.count
        guard characters.count >= n else { return nil }
        for start in 0...(characters.count - n) {
            let window = Array(characters[start..<(start + n)])
            guard window.allSatisfy(isHan) else { continue }
            let overlap = zip(window, valueChars)
                .filter { $0 == $1 || isHomophone(String($0), String($1)) }.count
            guard overlap >= 1 else { continue }
            let location = utf16Offsets[start]
            let end = start + n < characters.count ? utf16Offsets[start + n] : runningOffset
            qualifying.append((location, end - location, String(window)))
        }
        guard let first = qualifying.first,
              Set(qualifying.map(\.text)).count == 1
        else { return nil }
        return IntentPlanSourceReference(
            sourceID: unit.id,
            range: IntentSourceRange(
                location: unit.utf16Range.location + first.location,
                length: first.length),
            exactQuote: first.text)
    }

    private static func isHan(_ character: Character) -> Bool {
        String(character).range(of: #"^\p{Script=Han}$"#, options: .regularExpression) != nil
    }
}
