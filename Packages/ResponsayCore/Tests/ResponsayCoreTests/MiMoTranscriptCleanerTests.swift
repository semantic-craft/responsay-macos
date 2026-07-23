import Testing
@testable import ResponsayCore

// mimo-v2.5-asr is a reasoning model: it wraps the transcript as
// `<think>…</think>\n<lang> transcript`, and the chat template pre-fills `<think>`
// so the returned content starts with a MALFORMED `think>` (no opening `<`).
// `enable_thinking:false` is ignored by the endpoint. The raw content must be
// cleaned to the bare transcript before insertion. Fixtures are verbatim live
// responses from the Token-Plan endpoint.
@Suite struct MiMoTranscriptCleanerTests {
    @Test func stripsMalformedThinkPrefixAndLanguageTag() {
        // exact live output for English audio "The quick brown fox."
        #expect(MiMoTranscriptCleaner.clean("think>\n<chinese> The quick brown fox.")
            == "The quick brown fox.")
    }

    @Test func stripsProperThinkBlockWithReasoning() {
        #expect(MiMoTranscriptCleaner.clean("<think>let me transcribe</think>\n<english> Hello world")
            == "Hello world")
    }

    @Test func stripsChineseLanguageTag() {
        #expect(MiMoTranscriptCleaner.clean("think>\n<中文> 今天天气不错") == "今天天气不错")
    }

    @Test func leavesAlreadyCleanTranscriptUntouched() {
        #expect(MiMoTranscriptCleaner.clean("Just a plain transcript.") == "Just a plain transcript.")
    }

    @Test func trimsSurroundingWhitespace() {
        #expect(MiMoTranscriptCleaner.clean("  think>\n<english>  spaced out  ") == "spaced out")
    }

    @Test func doesNotEatRealAngleBracketsMidSentence() {
        // only a LEADING tag is a wrapper; a later "<" is real text.
        #expect(MiMoTranscriptCleaner.clean("think>\n<english> a < b in math")
            == "a < b in math")
    }
}
