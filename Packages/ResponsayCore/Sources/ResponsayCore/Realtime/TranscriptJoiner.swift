import Foundation

/// Joins successive final transcript fragments produced when the service splits
/// one utterance into several `completed` events (e.g. at a long in-sentence
/// pause in VAD mode).
///
/// A space is inserted **only** between two non-CJK word boundaries (Latin,
/// digits, …). CJK scripts (Chinese/Japanese, incl. full-width punctuation) do
/// not use inter-word spaces, so fragments on either side of a CJK boundary are
/// concatenated directly — otherwise a split Chinese sentence gains a spurious
/// mid-sentence space.
public enum TranscriptJoiner {
    public static func join(_ lhs: String, _ rhs: String) -> String {
        if lhs.isEmpty { return rhs }
        if rhs.isEmpty { return lhs }
        
        guard let last = lhs.unicodeScalars.last,
              let first = rhs.unicodeScalars.first else {
            return lhs + rhs
        }
        let needsSpace = !isCJK(last) && !isCJK(first)
        return needsSpace ? "\(lhs) \(rhs)" : lhs + rhs
    }

    /// Reduce a list of fragments to a single joined string.
    public static func join(_ fragments: [String]) -> String {
        fragments.reduce("") { join($0, $1) }
    }

    /// Concatenate already-final sentence segments, collapsing any exact boundary
    /// overlap between adjacent segments (openless `merge_segments`). Used to assemble
    /// Fun-ASR's per-`sentence_id` finals: an API replay / duplicate event can resurface
    /// a sentence whose head repeats the previous segment's tail, and a plain join would
    /// double it. Minimum overlap is 2 characters so a single-char coincidence
    /// (e.g. 「今天」+「天气」) is never merged; non-overlapping segments fall back to the
    /// CJK-aware `join`. Example: ["你好吗", "好吗我们"] → "你好吗我们".
    public static func mergeSegments(_ segments: [String]) -> String {
        var result = ""
        for segment in segments where !segment.isEmpty {
            if result.isEmpty { result = segment; continue }
            let resultChars = Array(result)
            let segmentChars = Array(segment)
            let maxOverlap = min(resultChars.count, segmentChars.count)
            var overlap = 0
            if maxOverlap >= 2 {
                for n in stride(from: maxOverlap, through: 2, by: -1)
                where resultChars.suffix(n) == segmentChars.prefix(n) {
                    overlap = n
                    break
                }
            }
            if overlap > 0 {
                result += String(segmentChars[overlap...])
            } else {
                result = join(result, segment)
            }
        }
        return result
    }

    /// Specialized join for cross-session reconnection. When a streaming session hits its
    /// max duration (e.g., 60s), the client reconnects and re-sends the last 2 seconds of
    /// audio to prevent truncation. This overlap causes overlapping text, which this
    /// method deduplicates by matching the suffix of `old` with the prefix of `new` —
    /// exactly first, then within a bounded fuzzy window for recognition drift (290①).
    public static func crossSessionJoin(_ old: String, _ new: String, minOverlap: Int = 2) -> String {
        guard !old.isEmpty else { return new }
        guard !new.isEmpty else { return old }

        let chars1 = Array(old)
        let chars2 = Array(new)
        var maxOverlap = 0

        let limit = min(chars1.count, chars2.count)
        if limit >= minOverlap {
            for length in minOverlap...limit {
                let suffix = chars1[(chars1.count - length)...]
                let prefix = chars2[0..<length]
                if suffix == prefix {
                    maxOverlap = length
                }
            }
        }

        if maxOverlap > 0 {
            return old + String(chars2[maxOverlap...])
        }
        if let drop = fuzzyOverlapNewPrefixLength(chars1, chars2) {
            return old + String(chars2[drop...])
        }
        return join(old, new)
    }

    /// 290①: the re-sent ~2s tail can be *decoded differently* by the new session
    /// (boundary drift, e.g. 「…合同法第五百条」+「同法第五百零二条…」) — exact
    /// matching finds nothing and the text duplicates. Within a 14-char budget
    /// (~2s of CJK speech) this looks for an old-suffix / new-prefix pair (length
    /// skew ≤ 2) whose edit distance ≤ max(1, ⌊min/3⌋). Fuzzy only engages from
    /// 5 chars up: short fragments at distance 1 (前半句话/后半句话) are plausibly
    /// genuine different text and must NOT be merged. The already-final `old`
    /// stays verbatim — committed text never mutates retroactively — and the
    /// drifted re-read is dropped from `new`'s head.
    private static func fuzzyOverlapNewPrefixLength(_ old: [Character], _ new: [Character]) -> Int? {
        let budget = 14
        let fuzzyFloor = 5
        let maxNew = min(budget, new.count)
        guard maxNew >= fuzzyFloor, old.count >= fuzzyFloor else { return nil }

        var best: (drop: Int, distance: Int)?
        for newLen in fuzzyFloor...maxNew {
            let prefix = Array(new.prefix(newLen))
            let oldLow = max(fuzzyFloor, newLen - 2)
            let oldHigh = min(min(budget, old.count), newLen + 2)
            guard oldLow <= oldHigh else { continue }
            for oldLen in oldLow...oldHigh {
                let suffix = Array(old.suffix(oldLen))
                // Cut-point anchor: both decodings must agree on the boundary
                // character — without it, a shorter mid-unit alignment (e.g.
                // 「…五百零」↔「…五百条」) wins on distance and leaves drifted
                // residue (「二条」) behind the cut.
                guard suffix.last == prefix.last else { continue }
                let allowed = max(1, min(oldLen, newLen) / 3)
                guard let distance = editDistance(suffix, prefix, cap: allowed) else { continue }
                if best == nil || newLen > best!.drop
                    || (newLen == best!.drop && distance < best!.distance) {
                    best = (newLen, distance)
                }
            }
        }
        return best?.drop
    }

    /// Plain Levenshtein with an early-out cap; `nil` when distance exceeds `cap`.
    /// Inputs are ≤ 14 chars (the fuzzy budget), so the DP stays trivial.
    private static func editDistance(_ a: [Character], _ b: [Character], cap: Int) -> Int? {
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + [Int](repeating: 0, count: b.count)
            var rowMin = i
            for j in 1...b.count {
                let substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
                current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
                rowMin = min(rowMin, current[j])
            }
            if rowMin > cap { return nil }
            previous = current
        }
        return previous[b.count] <= cap ? previous[b.count] : nil
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3000...0x303F, // CJK symbols & punctuation (，。、 …)
             0x3040...0x30FF, // Hiragana + Katakana
             0x3400...0x4DBF, // CJK Unified Ext A
             0x4E00...0x9FFF, // CJK Unified Ideographs
             0xF900...0xFAFF, // CJK Compatibility Ideographs
             0xFF00...0xFFEF, // Halfwidth & Fullwidth Forms
             0x20000...0x2FA1F: // CJK Ext B–F
            return true
        default:
            return false
        }
    }
}
