import Testing
import Foundation
@testable import ResponsayCore

/// Joining successive final fragments (when the service splits one utterance
/// into multiple `completed` events). The defect being pinned: a naive
/// space-join corrupts Chinese by inserting a space mid-sentence — the primary
/// legal/academic dictation case.
@Suite struct TranscriptJoinerTests {
    @Test func cjkFragmentsJoinWithoutSpace() {
        // The legalWriting/Chinese bug: split sentence must rejoin seamlessly.
        #expect(TranscriptJoiner.join("个人信息处理者，", "应当遵循正当性原则") == "个人信息处理者，应当遵循正当性原则")
    }

    @Test func latinFragmentsJoinWithSpace() {
        #expect(TranscriptJoiner.join("the agency", "must preserve oversight") == "the agency must preserve oversight")
    }

    @Test func cjkToLatinBoundaryHasNoSpace() {
        // Mixed zh/en: a Chinese run followed by an acronym stays glued.
        #expect(TranscriptJoiner.join("今天我们讨论", "CLSCI") == "今天我们讨论CLSCI")
    }

    @Test func emptyOperandsPassThrough() {
        #expect(TranscriptJoiner.join("", "x") == "x")
        #expect(TranscriptJoiner.join("x", "") == "x")
    }

    @Test func reduceJoinsManyFragments() {
        #expect(TranscriptJoiner.join(["前半句，", "后半句。"]) == "前半句，后半句。")
        #expect(TranscriptJoiner.join(["alpha", "beta", "gamma"]) == "alpha beta gamma")
    }

    // MARK: - crossSessionJoin (streaming session rotation, audit area 1)
    // The reconnect path re-sends the last ~2s of audio; the new session's first
    // transcript overlaps the old session's tail and must be deduplicated.

    @Test func crossSessionDeduplicatesOverlap() {
        #expect(TranscriptJoiner.crossSessionJoin("ABCDE", "DEFG") == "ABCDEFG")
        #expect(TranscriptJoiner.crossSessionJoin(
            "我们今天讨论合同法", "合同法第五百条") == "我们今天讨论合同法第五百条")
    }

    @Test func crossSessionPicksLongestOverlap() {
        // "ABAB" suffix vs "ABAB…" prefix: must take the 4-char overlap, not 2.
        #expect(TranscriptJoiner.crossSessionJoin("XYABAB", "ABABZ") == "XYABABZ")
    }

    @Test func crossSessionEmptyOperandsPassThrough() {
        #expect(TranscriptJoiner.crossSessionJoin("", "new") == "new")
        #expect(TranscriptJoiner.crossSessionJoin("old", "") == "old")
    }

    @Test func crossSessionNoOverlapFallsBackToPlainJoin() {
        // CJK-aware fallback: no space injected mid-sentence.
        #expect(TranscriptJoiner.crossSessionJoin("前半句话", "后半句话") == "前半句话后半句话")
    }

    @Test func crossSessionBelowMinOverlapIsNotDeduplicated() {
        // A single shared character is below minOverlap=2 — treated as no overlap.
        #expect(TranscriptJoiner.crossSessionJoin("AB", "BC") == "AB BC")
    }

    // 290① FIXED: recognition drift on the re-sent tail is deduplicated by the
    // bounded fuzzy overlap. Committed `old` text stays verbatim; the drifted
    // re-read is dropped from `new`'s head.
    @Test func crossSessionRecognitionDriftIsDeduplicated() {
        let old = "我们今天讨论合同法第五百条"
        let drifted = "同法第五百零二条的适用"  // re-sent tail recognized differently
        let joined = TranscriptJoiner.crossSessionJoin(old, drifted)
        #expect(joined == "我们今天讨论合同法第五百条的适用")
    }

    // 290① guard: fuzzy never merges *genuinely different* short text — a
    // 4-char pair at distance 1 (前半句话/后半句话) stays a plain join, and
    // wholly different sentences are untouched.
    @Test func crossSessionFuzzyDoesNotMergeDistinctText() {
        #expect(TranscriptJoiner.crossSessionJoin("前半句话", "后半句话") == "前半句话后半句话")
        #expect(TranscriptJoiner.crossSessionJoin(
            "今天天气很好", "我们去开会吧") == "今天天气很好我们去开会吧")
    }

    // 290① substitution drift: same audio re-read with one character decoded
    // differently mid-overlap (五百→五一) still deduplicates; `old` wins.
    @Test func crossSessionSubstitutionDriftIsDeduplicated() {
        let joined = TranscriptJoiner.crossSessionJoin(
            "我们今天讨论合同法第五百条", "合同法第五一条的适用")
        #expect(joined == "我们今天讨论合同法第五百条的适用")
    }
}
