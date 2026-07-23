import Foundation

/// `mimo-v2.5-asr` is a reasoning model. It returns the transcript wrapped as
/// `<think>…</think>\n<lang> transcript`, and because the chat template pre-fills
/// `<think>`, the returned content starts with a *malformed* `think>` (no opening
/// `<`). The endpoint ignores `enable_thinking:false`, so the noise must be
/// stripped client-side before the transcript is inserted. Only a LEADING wrapper
/// is removed — angle brackets later in the sentence are real text.
public enum MiMoTranscriptCleaner {
    public static func clean(_ raw: String) -> String {
        var s = raw

        // 1. A complete <think>…</think> block (case-insensitive, attributes tolerated).
        if let open = s.range(of: #"<think(\s[^>]*)?>"#, options: [.regularExpression, .caseInsensitive]),
           let close = s.range(of: "</think>", options: .caseInsensitive, range: open.upperBound..<s.endIndex) {
            s.removeSubrange(open.lowerBound..<close.upperBound)
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)

        // 2. A malformed leading think tag left by the pre-filled template: "think>",
        //    "</think>", "<think>" with nothing after.
        s = s.replacingOccurrences(
            of: #"^\s*(</?think[^>]*>|think\s*>)\s*"#,
            with: "", options: [.regularExpression, .caseInsensitive])

        // 3. A leading language tag: <chinese> / <english> / <中文> …  (letters only,
        //    so a real "<" mid-sentence is never matched).
        s = s.replacingOccurrences(
            of: #"^\s*<[\p{L}]+>\s*"#,
            with: "", options: .regularExpression)

        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
