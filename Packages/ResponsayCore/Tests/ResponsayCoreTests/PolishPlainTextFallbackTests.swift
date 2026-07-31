import Testing
import Foundation
@testable import ResponsayCore

/// The polish reply → `PolishResult` mapping, including the plain-text fallback that fixes the
/// "offline dictation has no punctuation" bug (a model that ignores the {text, changes} envelope
/// must NOT make dictation degrade to the unpunctuated verbatim transcript). Pure — no HTTP.
struct PolishPlainTextFallbackTests {

    // MARK: - Preferred {text, changes} envelope

    @Test func jsonEnvelope_returnsText_fillsOriginalFromInput() {
        let r = PolishPlainTextFallback.result(
            fromRaw: #"{"text":"今天天气不错，我们去图书馆。","changes":["补标点"]}"#,
            input: "今天天气不错我们去图书馆")
        #expect(r?.text == "今天天气不错，我们去图书馆。")
        #expect(r?.original == "今天天气不错我们去图书馆")   // filled from input, not the model
        #expect(r?.changes == ["补标点"])
    }

    @Test func fencedJSON_isParsed() {
        let r = PolishPlainTextFallback.result(
            fromRaw: "```json\n{\"text\":\"好的。\",\"changes\":[]}\n```", input: "好的")
        #expect(r?.text == "好的。")
        #expect(r?.changes == [])
    }

    // MARK: - Plain-text fallback (the bug fix)

    @Test func plainText_isAccepted_asTheTidiedResult() {
        // qwen3.6-flash may return the tidied transcript as PLAIN TEXT.
        let r = PolishPlainTextFallback.result(
            fromRaw: "今天天气不错，我们一起去图书馆看书。", input: "今天天气不错我们一起去图书馆看书")
        #expect(r?.text == "今天天气不错，我们一起去图书馆看书。")
        #expect(r?.original == "今天天气不错我们一起去图书馆看书")
        #expect(r?.changes == [])
    }

    @Test func fencedPlainText_stripsFence() {
        let r = PolishPlainTextFallback.result(fromRaw: "```\nHello, world.\n```", input: "hello world")
        #expect(r?.text == "Hello, world.")
    }

    @Test func plainText_trimsSurroundingWhitespace() {
        let r = PolishPlainTextFallback.result(fromRaw: "\n  整理后的句子。 \n", input: "整理后的句子")
        #expect(r?.text == "整理后的句子。")
    }

    // MARK: - Unusable replies → nil (caller throws; dictation keeps verbatim, no regression)

    @Test func empty_isNil() {
        #expect(PolishPlainTextFallback.result(fromRaw: "", input: "x") == nil)
        #expect(PolishPlainTextFallback.result(fromRaw: "   \n  ", input: "x") == nil)
    }

    @Test func brokenJSONObject_isNil_notInsertedRaw() {
        // A `{…}` that failed to parse is malformed structured output, not prose — inserting it
        // raw would leak braces into the user's document, so reject it (→ verbatim, as before).
        #expect(PolishPlainTextFallback.result(fromRaw: #"{"text":"oops" "changes":}"#, input: "x") == nil)
        #expect(PolishPlainTextFallback.result(fromRaw: "[unterminated", input: "x") == nil)
    }

    @Test func jsonWithEmptyText_fallsThroughToNil_notAnEmptyInsert() {
        // Valid JSON but blank "text" must not insert an empty string; the raw starts with `{`
        // so the plain-text fallback also rejects it → nil.
        #expect(PolishPlainTextFallback.result(fromRaw: #"{"text":"","changes":[]}"#, input: "x") == nil)
    }

    // MARK: - usablePlainText guard

    @Test func usablePlainText_rejectsStructuredPrefixes() {
        #expect(PolishPlainTextFallback.usablePlainText(from: "正常的一句话。") == "正常的一句话。")
        #expect(PolishPlainTextFallback.usablePlainText(from: "{not json") == nil)
        #expect(PolishPlainTextFallback.usablePlainText(from: "[1,2") == nil)
        #expect(PolishPlainTextFallback.usablePlainText(from: "   ") == nil)
    }

    // MARK: - openless-style leading-boilerplate stripping (preamble leak defence)

    @Test func plainText_stripsLeadingBoilerplate_colonAndPeriod() {
        // "整理如下：…" / "以下是整理后的内容。…" preambles a model leaks must NOT be inserted.
        #expect(PolishPlainTextFallback.result(
            fromRaw: "整理如下：今天天气不错，我们去图书馆。", input: "今天天气不错我们去图书馆")?.text
            == "今天天气不错，我们去图书馆。")
        #expect(PolishPlainTextFallback.result(
            fromRaw: "以下是整理后的内容。这是结果。", input: "x")?.text == "这是结果。")
    }

    @Test func plainText_stripsStackedBoilerplate() {
        #expect(PolishPlainTextFallback.usablePlainText(
            from: "根据您给的内容，整理如下：最终文本。") == "最终文本。")
    }

    @Test func plainText_boilerplateOnly_noBody_isNil() {
        // Just a preamble with no real content → nothing usable → verbatim (no regression).
        #expect(PolishPlainTextFallback.usablePlainText(from: "整理如下") == nil)
    }

    @Test func plainText_leavesNormalSentenceUntouched() {
        // A real sentence that merely starts with similar words isn't over-stripped.
        #expect(PolishPlainTextFallback.usablePlainText(from: "整理工作已经完成了。")
            == "整理工作已经完成了。")
    }
}

// MARK: - #581 salvage tier (malformed envelope with unescaped inner quotes)

@Test func salvagesEnvelopeWithUnescapedInnerQuotes() {
    // mimo's real reply shape from the live eval: valid-looking envelope, invalid JSON.
    let raw = #"{"text": "他刚才说"不对，是周五"，你记一下这句话。", "changes": []}"#
    let result = PolishPlainTextFallback.result(fromRaw: raw, input: "原话")
    #expect(result?.text == #"他刚才说"不对，是周五"，你记一下这句话。"#)
    #expect(result?.changes.isEmpty == true)
}

@Test func salvageRefusesBrokenObjectsWithoutBothMarkers() {
    // No "changes" tail → not salvageable → still nil (never insert raw braces).
    #expect(PolishPlainTextFallback.result(fromRaw: #"{"text": "半截"#, input: "x") == nil)
    #expect(PolishPlainTextFallback.result(fromRaw: #"{"foo": "bar", "changes": []}"#, input: "x") == nil)
}
