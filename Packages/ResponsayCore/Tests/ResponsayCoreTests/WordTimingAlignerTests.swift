import Testing
import Foundation
@testable import ResponsayCore

/// 135 — TTS word-timing alignment + fallback ladder.
/// Verification: token≠word alignment; fallback duration sum equals segment duration.
struct WordTimingAlignerTests {
    private let aligner = DefaultWordTimingAligner()

    @Test func providerWordTiming_isPreferred() {
        let provider = [
            TimedWord(text: "Hello", startTime: 0, endTime: 0.4),
            TimedWord(text: "world", startTime: 0.4, endTime: 0.9),
        ]
        let result = aligner.align(text: "Hello world", providerTiming: provider, audioDuration: 0.9)
        #expect(result == provider)            // word-level provider timing trusted as-is
    }

    @Test func greedyAlign_whenTokensFinerThanWords() {
        // Provider tokenized "Hello" into two sub-tokens; canonical word is one.
        let tokens = [
            TimedWord(text: "Hel", startTime: 0.0, endTime: 0.2),
            TimedWord(text: "lo", startTime: 0.2, endTime: 0.4),
            TimedWord(text: "world", startTime: 0.4, endTime: 0.9),
        ]
        let result = aligner.align(text: "Hello world", providerTiming: tokens, audioDuration: 0.9)
        #expect(result.count == 2)
        #expect(result[0].text == "Hello")
        #expect(result[0].startTime == 0.0)
        #expect(result[0].endTime == 0.4)       // merged across both sub-tokens
        #expect(result[1].text == "world")
        #expect(result[1].endTime == 0.9)
    }

    @Test func proportionalFallback_sumsToDuration() {
        let result = aligner.align(text: "one two three", providerTiming: nil, audioDuration: 6.0)
        #expect(result.count == 3)
        #expect(result.first?.startTime == 0)
        #expect(result.last?.endTime == 6.0)    // snapped to segment duration
        // contiguous: each word's end == next word's start
        for i in 1..<result.count {
            #expect(result[i].startTime == result[i - 1].endTime)
        }
    }

    @Test func proportionalFallback_weightsByLength() {
        // "aaaa" (4) vs "b" (1) → 5 weight units over 5s → 4s + 1s.
        let result = DefaultWordTimingAligner.proportionalTimings(words: ["aaaa", "b"], duration: 5.0)
        #expect(abs(result[0].endTime - 4.0) < 0.0001)
        #expect(result[1].startTime == result[0].endTime)
        #expect(result[1].endTime == 5.0)
    }

    @Test func sentenceLevel_whenNoWordTiming() {
        let result = aligner.sentenceTiming(text: "no word timing available here", duration: 3.5)
        #expect(result.count == 1)
        #expect(result[0].startTime == 0)
        #expect(result[0].endTime == 3.5)
    }

    @Test func clickWordSeek_resolvesTimeToWord() {
        let timings = aligner.align(text: "one two three", providerTiming: nil, audioDuration: 6.0)
        // a time inside the second word resolves to index 1; its start is the seek point
        let mid = (timings[1].startTime + timings[1].endTime) / 2
        #expect(DefaultWordTimingAligner.wordIndex(at: mid, in: timings) == 1)
        #expect(DefaultWordTimingAligner.wordIndex(at: 0, in: timings) == 0)
        #expect(DefaultWordTimingAligner.wordIndex(at: 6.0, in: timings) == 2) // end claimed by last
    }

    @Test func cjkText_tokenizesPerCharacter() {
        let result = aligner.align(text: "你好世界", providerTiming: nil, audioDuration: 4.0)
        #expect(result.count == 4)
        #expect(result.last?.endTime == 4.0)
    }

    @Test func emptyText_yieldsNoTimings() {
        #expect(aligner.align(text: "   ", providerTiming: nil, audioDuration: 2.0).isEmpty)
    }
}
