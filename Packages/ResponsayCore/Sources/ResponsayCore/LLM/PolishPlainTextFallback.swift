import Foundation

/// Maps a 轻改写 (polish) model reply to a `PolishResult`, tolerating models that ignore the
/// `{text, changes}` JSON envelope.
///
/// Why this exists: the polish prompt asks for `{"text":…, "changes":[…]}`, but the cloud path
/// deliberately does NOT send a `response_format` json_schema (several BYOK providers 400 on it,
/// see `LLMChatRequestBuilder`), so a small/fast model (e.g. a `*-flash`) often just returns the
/// tidied transcript as PLAIN TEXT. The old code threw `badJSON` in that case; the dictation
/// transformer then silently degraded to the **unpunctuated verbatim transcript** — the
/// "offline dictation has no punctuation" bug.
///
/// Design (hybrid, a strict superset of openless's polish):
/// - JSON-first: a model that complies (e.g. DeepSeek) still gives us `{text, changes}`, so the
///   review/history "changes" notes are preserved and that path is unchanged (no regression).
/// - Plain-text fallback: when the envelope is missing, accept the content as the result — this
///   is exactly how openless's `polish.rs` treats every reply (`extract_assistant_content` →
///   `clean_polish_output`). We port its defensive cleanup (markdown fence + leading boilerplate)
///   so a "整理如下：…" / "以下是…" preamble a model leaks doesn't get inserted into the document.
///
/// Pure + synchronous so the selection logic is unit-tested without any HTTP. (`<think>` blocks are
/// already stripped upstream in `LLMChatClient.execute`.)
enum PolishPlainTextFallback {
    /// Preferred path: the `{text, changes}` envelope. Fallback: a cleaned plain-text reply.
    /// `nil` means the reply is unusable (empty, or a broken structured object we shouldn't
    /// insert raw) — the caller throws `badJSON` and the dictation keeps the verbatim transcript.
    static func result(fromRaw raw: String, input: String) -> PolishResult? {
        if let obj = LLMResponseParsing.jsonObject(from: raw) {
            let outText = LLMResponseParsing.string(obj, "text")
            if !outText.isEmpty {
                return PolishResult(
                    text: outText,
                    original: input,
                    changes: LLMResponseParsing.stringArray(obj, "changes"))
            }
        }
        // #581: middle tier — a malformed envelope whose answer is still visibly there.
        // mimo emits unescaped inner quotes (`{"text": "他说"不对"…", "changes": []}`): invalid
        // JSON, but refusing it degraded dictation to the verbatim transcript for no reason.
        if let salvaged = salvagedEnvelopeText(from: raw) {
            return PolishResult(text: salvaged, original: input, changes: [])
        }
        guard let plain = usablePlainText(from: raw) else { return nil }
        // No change notes from a plain-text reply — the tidy actions weren't enumerated.
        return PolishResult(text: plain, original: input, changes: [])
    }

    /// Recover the text of an envelope that failed JSON parsing because the model left inner
    /// double quotes unescaped. BOTH markers must be present — the `"text": "` opener and the
    /// `", "changes"` tail (searched from the end) — so this never guesses on arbitrary broken
    /// JSON, and a brace-leaking reply still returns nil downstream.
    static func salvagedEnvelopeText(from raw: String) -> String? {
        let trimmed = stripCodeFence(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") else { return nil }
        guard let open = trimmed.range(of: #""text"\s*:\s*""#, options: .regularExpression),
              let close = trimmed.range(
                  of: #""\s*,\s*"changes""#, options: [.regularExpression, .backwards]),
              close.lowerBound > open.upperBound
        else { return nil }
        let inner = String(trimmed[open.upperBound..<close.lowerBound])
        let unescaped = inner
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
        let text = unescaped.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// A plain-text polish reply, cleaned the way openless's `clean_polish_output` does: strip a
    /// whole-reply code fence, then iteratively strip a known leading boilerplate phrase. Returns
    /// `nil` when nothing usable is left, or when the remainder is an attempted-but-broken
    /// structured object (a leading `{`/`[` that `jsonObject` already failed to parse — inserting
    /// it raw would leak braces into the document).
    static func usablePlainText(from raw: String) -> String? {
        var text = stripCodeFence(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        text = stripLeadingBoilerplate(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        guard !text.hasPrefix("{"), !text.hasPrefix("[") else { return nil }
        return text
    }

    /// Strip a single ```…``` markdown fence (``` or ```lang) if the whole reply is fenced.
    private static func stripCodeFence(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("```") else { return s }
        if let firstNewline = s.firstIndex(of: "\n") { s = String(s[s.index(after: firstNewline)...]) }
        if let fence = s.range(of: "```", options: .backwards) { s = String(s[..<fence.lowerBound]) }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Known "introduction" phrases some models prepend even when prompted not to. Ported verbatim
    /// from openless `polish.rs::LEADING_BOILERPLATE_PREFIXES`.
    private static let leadingBoilerplatePrefixes = [
        "根据您给的内容", "根据您提供的内容", "根据你给的内容", "根据你提供的内容",
        "以下是整理后的内容", "以下是优化后的内容", "以下为整理后的内容", "以下是结构化整理后的内容",
        "我整理如下", "我已整理如下", "整理如下", "优化如下", "结构化整理如下",
    ]

    /// Sentence/clause terminators that bound a boilerplate prefix (openless `BOILERPLATE_END_CHARS`).
    private static let boilerplateEndChars: Set<Character> = ["。", "：", ":", "，", ",", "\n"]

    /// Iteratively drop a leading boilerplate phrase (and the clause up to its first terminator),
    /// so stacked preambles are all removed — openless `clean_polish_output`'s loop.
    private static func stripLeadingBoilerplate(_ text: String) -> String {
        var output = text
        while true {
            let stripped = stripLeadingBoilerplateOnce(output)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if stripped == output { return output }
            output = stripped
        }
    }

    private static func stripLeadingBoilerplateOnce(_ text: String) -> String {
        for prefix in leadingBoilerplatePrefixes where text.hasPrefix(prefix) {
            let afterPrefix = text[text.index(text.startIndex, offsetBy: prefix.count)...]
            if let terminator = afterPrefix.firstIndex(where: { boilerplateEndChars.contains($0) }) {
                return String(afterPrefix[afterPrefix.index(after: terminator)...])
            }
            return String(afterPrefix)   // no terminator: drop the prefix only
        }
        return text
    }
}
