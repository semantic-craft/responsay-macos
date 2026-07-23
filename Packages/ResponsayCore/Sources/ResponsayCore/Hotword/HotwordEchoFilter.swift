import Foundation

/// Drops the "biasing-list echo": a cloud multimodal ASR handed near-empty audio
/// sometimes returns its own injected hotword hint verbatim (e.g. "CLSCI, SSRN,
/// Westlaw, arXiv, DOI, …") instead of a transcript. That non-empty string then
/// slips past `ASRHTTPGuards.nonEmpty` and gets inserted into the focused app.
///
/// Signature of the echo: a comma/、/；-separated LIST whose every segment is a known
/// biasing term. We require ≥2 segments so a legitimate one-word dictation of a single
/// hotword ("arXiv") is never dropped, and we never split on spaces — multi-word terms
/// like "et al." stay intact. Real prose fails the all-segments-are-terms test.
public enum HotwordEchoFilter {
    /// `true` when `transcript` is nothing but a list of `terms` echoed back.
    public static func isEcho(_ transcript: String, terms: [String]) -> Bool {
        let termSet = Set(terms.map(normalize).filter { !$0.isEmpty })
        guard !termSet.isEmpty else { return false }
        // List separators only — NOT whitespace, so "et al." / "ibid." survive as one segment.
        let separators = CharacterSet(charactersIn: ",，、;；\n\t")
        let segments = transcript
            .components(separatedBy: separators)
            .map(normalize)
            .filter { !$0.isEmpty }
        guard segments.count >= 2 else { return false }
        return segments.allSatisfy { termSet.contains($0) }
    }

    /// Trim whitespace AND period-class punctuation from both ends: the ASR re-punctuates each
    /// echoed item, so a dot-terminated seed ("et al.") comes back as "et al.." and the last list
    /// item often gains a 。 — without this, that drift fails the exact-match and the whole echo
    /// slips through. Internal dots (e.g. "U.S.") survive — only the ends are trimmed.
    private static let trimSet = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".。·｡．"))

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: trimSet).lowercased()
    }
}
