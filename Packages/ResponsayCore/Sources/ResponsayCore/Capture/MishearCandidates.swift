import Foundation

/// The ASCII "proper-noun / brand / code" shaped tokens ASR most often mis-hears, and the
/// self-explanatory「纠正」chip label built from them.
///
/// User 2026-07-06: a bare「纠正…」left first-time users unsure what the chip was for. Naming the
/// suspected word makes the offer obvious —「DeepSeek」听对了吗？— because it points at the exact
/// thing to check rather than asking the user to guess which word was misheard.
///
/// The shape rule lives here as the single source of truth, shared with the chip's show/hide gate
/// (`QuickCaptureViewModel.looksLikeMishearCandidate`), so the label and the gate never disagree.
public enum MishearCandidates {
    /// Longest term shown on the pill before truncating with an ellipsis, so one very long code
    /// term can't stretch the floating capsule off-screen.
    static let displayCap = 16

    /// The shaped tokens in `text`, in first-seen order, deduped. Empty for plain prose.
    static func tokens(in text: String) -> [String] {
        var seen = Set<Substring>()
        var out: [String] = []
        for token in text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) where isShaped(token) {
            if seen.insert(token).inserted { out.append(String(token)) }
        }
        return out
    }

    /// The「纠正」chip title — names the first suspected word, appends 等词 when there's more than
    /// one, and falls back to a generic prompt when nothing is shaped (the「每次都显示」case on
    /// plain Chinese, where the chip is forced on with no specific word to point at).
    public static func chipTitle(for text: String) -> String {
        let found = tokens(in: text)
        guard let first = found.first else { return "有词听错了？点我纠正" }
        let shown = first.count > displayCap ? String(first.prefix(displayCap)) + "…" : first
        return found.count > 1 ? "「\(shown)」等词听对了吗？" : "「\(shown)」听对了吗？"
    }

    /// One ASCII token shaped like a mis-heard proper noun / brand / code term: contains a digit,
    /// an interior capital (DeepSeek), or is Capitalized-with-lowercase (Metapocalypse, Matt).
    /// (Hyphens split tokens, so `Qwen3-ASR` still matches via its digit-bearing half.) Same shape
    /// family as `RuleBasedHotwordCandidateExtractor.hasHotwordShape`, without its repeat-count
    /// requirement — one shaped token in a single fresh utterance is already a meaningful signal.
    static func isShaped(_ token: Substring) -> Bool {
        guard token.count >= 2, token.contains(where: { $0.asciiValue != nil }) else { return false }
        let hasUpper = token.contains(where: \.isUppercase)
        let hasLower = token.contains(where: \.isLowercase)
        if token.contains(where: \.isNumber) { return true }
        if token.contains("-"), hasUpper { return true }
        if hasUpper, hasLower, token.dropFirst().contains(where: \.isUppercase) { return true }
        if let first = token.first?.asciiValue, (65...90).contains(first), hasLower { return true }
        return false
    }
}
