import Foundation

/// Builds the pre-numbered entity candidate table (#562) from whitelisted grounding sources, in
/// fixed provenance priority: spoken clues → confirmed aliases → dictionary terms → allowed
/// context tokens. Deterministic IDs (`entity-0000`…), each slot fully inside ONE source unit.
/// Overlapping slots with different values are kept — the finalizer turns a selection touching a
/// contested slot into needs-review with the alternatives (spec decision 16: 唯一或弃权).
public enum IntentEntityCandidateTable {
    static let maxCandidates = 16
    private static let privacyGate = LexicalProfilePrivacyGate()

    public static func build(
        transcript: String,
        units: [IntentSourceUnit],
        grounding: IntentGroundingSources
    ) -> [IntentEntityCandidate] {
        var entries = [(value: String, provenance: IntentEntityCandidate.Provenance, target: IntentPlanSourceReference)]()

        for extraction in IntentSpokenClueExtractor.extract(transcript: transcript, units: units) {
            guard let target = extraction.target else { continue }   // ambiguous referent → review path
            entries.append((extraction.value, .spokenClue, target))
        }
        for alias in grounding.aliases {
            for target in occurrences(of: alias.surface, in: transcript, units: units)
            where alias.canonical != alias.surface {
                entries.append((alias.canonical, .confirmedAlias, target))
            }
        }
        for term in grounding.dictionaryTerms {
            for target in normalizedOccurrences(of: term, in: transcript, units: units) {
                entries.append((term, .dictionary, target))
            }
        }
        for token in contextTokens(in: grounding.contextTexts) {
            for target in normalizedOccurrences(of: token, in: transcript, units: units) {
                entries.append((token, .allowedContext, target))
            }
        }

        var seen = Set<String>()
        var candidates = [IntentEntityCandidate]()
        for entry in entries {
            let key = "\(entry.value)@\(entry.target.range.location):\(entry.target.range.length)"
            guard seen.insert(key).inserted else { continue }
            guard candidates.count < maxCandidates else { break }
            candidates.append(IntentEntityCandidate(
                id: String(format: "entity-%04d", candidates.count),
                value: entry.value,
                provenance: entry.provenance,
                target: entry.target))
        }
        return candidates
    }

    /// Candidates whose slots overlap the given candidate's slot with a DIFFERENT value — the
    /// contested-slot group that forces review instead of silent auto-normalization.
    public static func conflicts(
        with candidate: IntentEntityCandidate,
        in table: [IntentEntityCandidate]
    ) -> [IntentEntityCandidate] {
        table.filter { other in
            other.id != candidate.id
                && other.value != candidate.value
                && other.target.sourceID == candidate.target.sourceID
                && overlaps(other.target.range, candidate.target.range)
        }
    }

    // MARK: - Matching

    /// Literal occurrences (used for alias surfaces — the exact misheard spelling).
    private static func occurrences(
        of needle: String,
        in transcript: String,
        units: [IntentSourceUnit]
    ) -> [IntentPlanSourceReference] {
        matches(of: needle, in: transcript, units: units, options: [])
    }

    /// Case/width-normalized occurrences whose surface DIFFERS from the canonical value —
    /// same word, wrong spelling in the transcript (paddleocr → PaddleOCR).
    private static func normalizedOccurrences(
        of canonical: String,
        in transcript: String,
        units: [IntentSourceUnit]
    ) -> [IntentPlanSourceReference] {
        matches(of: canonical, in: transcript, units: units, options: [.caseInsensitive, .widthInsensitive])
            .filter { $0.exactQuote != canonical }
    }

    private static func matches(
        of needle: String,
        in transcript: String,
        units: [IntentSourceUnit],
        options: NSString.CompareOptions
    ) -> [IntentPlanSourceReference] {
        guard !needle.isEmpty else { return [] }
        let ns = transcript as NSString
        var found = [IntentPlanSourceReference]()
        var search = NSRange(location: 0, length: ns.length)
        while search.length > 0 {
            let range = ns.range(of: needle, options: options, range: search)
            guard range.location != NSNotFound else { break }
            let sourceRange = IntentSourceRange(location: range.location, length: range.length)
            if let unit = units.first(where: { sourceRange.isWithin($0.utf16Range) }) {
                found.append(IntentPlanSourceReference(
                    sourceID: unit.id,
                    range: sourceRange,
                    exactQuote: ns.substring(with: range)))
            }
            let next = range.location + max(range.length, 1)
            search = NSRange(location: next, length: ns.length - next)
        }
        return found
    }

    /// Latin-ish tokens from allowed context text, privacy-gated. Context is candidate
    /// EVIDENCE — free text in it can never become an instruction, only a spelling surface.
    private static func contextTokens(in texts: [String]) -> [String] {
        var tokens = [String]()
        var seen = Set<String>()
        for text in texts {
            guard privacyGate.rejectionReason(text: text) == nil else { continue }
            let pieces = text.components(separatedBy: CharacterSet.alphanumerics.inverted)
            for piece in pieces {
                guard piece.count >= 3, piece.count <= 30,
                      piece.rangeOfCharacter(from: .letters) != nil,
                      seen.insert(piece).inserted,
                      privacyGate.rejectionReason(text: piece) == nil
                else { continue }
                tokens.append(piece)
            }
        }
        return tokens
    }

    private static func overlaps(_ lhs: IntentSourceRange, _ rhs: IntentSourceRange) -> Bool {
        lhs.location < rhs.location + rhs.length && rhs.location < lhs.location + lhs.length
    }
}
