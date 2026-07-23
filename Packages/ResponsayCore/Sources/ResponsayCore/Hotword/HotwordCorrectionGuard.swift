import Foundation

/// Divergence backstop for the optional LLM correction tier (#500 S3). The only legitimate edit is
/// swapping a near-miss surface for a registered candidate term — so the guard is **candidate-aware**
/// (review hardening), not merely size-based: any character the reply introduces must belong to a
/// candidate term, and the length must stay swap-stable. This rejects what a coarse length/edit band
/// let through — short unspoken insertions (核心), appended clauses, dropped spoken words, and
/// same-length paraphrases (说→讲) — keeping the LLM advisory and the transcript faithful (ADR-0008).
public enum HotwordCorrectionGuard {

    /// The text to insert: the corrected reply when it passes the candidate-aware checks, else the
    /// original (the LLM is advisory, never authoritative).
    public static func resolved(original: String, corrected: String, candidates: [String]) -> String {
        accept(original: original, corrected: corrected, candidates: candidates) ? corrected : original
    }

    /// True when `corrected` differs from `original` only by introducing candidate-term characters,
    /// with a swap-stable length.
    public static func accept(original: String, corrected: String, candidates: [String]) -> Bool {
        let o = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let c = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !c.isEmpty, !o.isEmpty else { return false }
        if c == o { return true }   // a no-op reply is trivially safe

        // Candidate terms the reply actually swapped IN (present in corrected, absent from the
        // original): only these authorize extra shrink/edit slack (#516). An English wild miss
        // ("meta poll clock" → "Matt Pocock") legitimately shrinks and diverges far more than a
        // CJK near-miss; the whitelist keeps that relaxation swap-scoped — a reply that introduces
        // no new candidate gets no slack (so dropping spoken words is still rejected).
        let introducedLength = candidates
            .filter { c.contains($0) && !o.contains($0) }
            .reduce(0) { $0 + $1.count }

        // 1. Swap-stable length: a near-miss→term swap barely changes length. The upward slack is
        //    bounded by the actual candidate terms (a swapped-in term can be a few chars longer than
        //    its misheard surface); shrink is allowed only for a newly-introduced candidate (whose
        //    misheard surface can be longer than the term) — otherwise spoken content was dropped.
        let grow = candidates.reduce(2) { $0 + $1.count }
        guard c.count <= o.count + grow, c.count >= o.count - 1 - introducedLength else { return false }

        // 2. Every character the reply introduces (not in the original) must belong to a candidate
        //    term — the model may only substitute a misheard surface for a registered term, never add
        //    prose, punctuation, or a paraphrase of a non-candidate word.
        let originalChars = Set(o)
        let candidateChars = Set(candidates.joined())
        guard c.allSatisfy({ originalChars.contains($0) || candidateChars.contains($0) }) else { return false }

        // 3. Aggregate edit stays bounded (defence in depth against same-length churn within the
        //    candidate character set); a newly-introduced candidate widens the band by its own size.
        return HotwordHardMatch.levenshtein(o, c) <= max(max(4, o.count / 4), introducedLength + 2)
    }
}
