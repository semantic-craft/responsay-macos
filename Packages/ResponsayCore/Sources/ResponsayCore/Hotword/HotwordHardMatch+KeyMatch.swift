import Foundation

// ASCII key normalization + edit-distance for the Latin near-miss pass. Split out of
// HotwordHardMatch (file ≤400 lines); same enum namespace, callers stay unqualified.
extension HotwordHardMatch {

    /// Lowercase + strip everything but ASCII `[a-z0-9]` — the comparison space in
    /// which "C L S C I", "clsci", and "CLSCI" all collapse to the same key.
    static func normalizeKey(_ value: String) -> String {
        var out = ""
        out.reserveCapacity(value.count)
        for character in value {
            guard let ascii = character.asciiValue else { continue }
            switch ascii {
            case 48...57, 97...122:                       // 0-9, a-z
                out.unicodeScalars.append(UnicodeScalar(ascii))
            case 65...90:                                  // A-Z → lower
                out.unicodeScalars.append(UnicodeScalar(ascii + 32))
            default:
                continue
            }
        }
        return out
    }

    static func maxDistance(forLength length: Int) -> Int {
        switch length {
        case ...4: return 0
        case ...8: return 1
        case ...12: return 2
        default: return 3
        }
    }

    /// Consonant phonetic skeleton over a normalized ASCII key: vowels dropped, c/k/q→k, z/x→s,
    /// v→f, y→i, adjacent repeats collapsed — the "sounds like the same word" comparison space.
    /// Shared home (#516): used by the auto-learn anti-junk gate (`RuleBasedHotwordCandidateExtractor`)
    /// and the LLM correction tier's English retrieval (`HotwordCorrectionCandidates`), so the two
    /// callers can't drift.
    static func phoneticKey(_ key: String) -> String {
        var out = ""
        var previous: Character?
        for character in key {
            let mapped: Character
            switch character {
            case "c", "k", "q": mapped = "k"
            case "x": mapped = "s"
            case "z": mapped = "s"
            case "v": mapped = "f"
            case "y": mapped = "i"
            case "a", "e", "i", "o", "u": continue
            default: mapped = character
            }
            if mapped != previous {
                out.append(mapped)
                previous = mapped
            }
        }
        return out
    }

    /// Classic two-row Levenshtein over the normalized (ASCII) keys.
    static func levenshtein(_ a: String, _ b: String) -> Int {
        if a == b { return 0 }
        let aChars = Array(a)
        let bChars = Array(b)
        var row = Array(0...bChars.count)
        for i in 1...max(aChars.count, 1) where !aChars.isEmpty {
            var previous = row[0]
            row[0] = i
            for j in 1...bChars.count {
                let temp = row[j]
                row[j] = aChars[i - 1] == bChars[j - 1]
                    ? previous
                    : Swift.min(previous + 1, row[j] + 1, row[j - 1] + 1)
                previous = temp
            }
        }
        return row[bChars.count]
    }
}
