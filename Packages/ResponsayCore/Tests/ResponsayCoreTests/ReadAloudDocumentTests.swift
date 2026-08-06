import Testing
import Foundation
@testable import ResponsayCore

/// Slicing a pasted document into the units the reader speaks and highlights.
struct ReadAloudScriptTests {
    /// Sentences long enough to be worth their own synthesis request stay separate — one
    /// sentence, one exactly-timed highlight span.
    @Test func splitsChineseParagraphOnSentencePunctuation() {
        let script = ReadAloudScript(text: Self.first + Self.second)

        #expect(script.count == 2)
        #expect(script[0]?.text == Self.first)
        #expect(script[1]?.text == Self.second)
    }

    /// Very short neighbours are deliberately merged by `TTSTextChunker` (a 7-character
    /// synthesis request costs a round trip to say almost nothing). The highlight is coarser
    /// for staccato text as a result — an accepted trade, pinned here so it stays a decision
    /// rather than a surprise.
    @Test func mergesSentencesTooShortToSynthesizeAlone() {
        let script = ReadAloudScript(text: "好的。知道了。这就去办。")

        #expect(script.count == 1)
        #expect(script[0]?.text == "好的。知道了。这就去办。")
    }

    /// Paragraph identity survives slicing — the reader lays the document out by paragraph.
    @Test func keepsParagraphIndices() {
        let script = ReadAloudScript(text: """
            \(Self.first)\(Self.second)
            \(Self.third)
            """)

        #expect(script.paragraphCount == 2)
        #expect(script.lines(inParagraph: 0).count == 2)
        #expect(script.lines(inParagraph: 1).count == 1)
        #expect(script.lines.map(\.id) == [0, 1, 2])
    }

    /// Line ids are the highlight index, so they must be dense and in reading order even
    /// across paragraph boundaries.
    @Test func numbersLinesContiguouslyAcrossParagraphs() {
        let script = ReadAloudScript(text: """
            \(Self.first)\(Self.second)
            \(Self.third)\(Self.first)
            \(Self.second)
            """)

        #expect(script.lines.map(\.id) == Array(0..<script.count))
        #expect(script.lines.map(\.paragraph) == [0, 0, 1, 1, 2])
    }

    // Sentences from a real passage, each past the chunker's merge floor so they slice
    // one-to-one — the ordinary case for prose someone would paste in to be read.
    private static let first = "人工智能生成内容的著作权归属，目前在各国立法中仍无定论。"
    private static let second = "多数意见认为，只有当人类在创作过程中作出了实质性的智力投入时，其成果才可能构成受保护的作品。"
    private static let third = "欧盟的路径有所不同，人工智能法案着眼于透明度义务与风险分级，并未直接处理产出物的权利归属。"

    @Test func blankInputProducesNoLines() {
        #expect(ReadAloudScript(text: "   \n\n  ").isEmpty)
        #expect(ReadAloudScript(text: "").count == 0)
    }

    /// A wall of text with no sentence punctuation still has to become speakable pieces —
    /// otherwise a paste of run-on prose would be one enormous synthesis request.
    @Test func softSplitsRunOnText() {
        let runOn = String(repeating: "很长的一段没有句号的文字，", count: 40)
        let script = ReadAloudScript(text: runOn)

        #expect(script.count > 1)
        #expect(script.lines.allSatisfy { $0.text.count <= TTSChunkingPolicy.default.maxChars })
    }

    @Test func remainingCharactersCountsFromTheGivenLine() {
        let script = ReadAloudScript(text: Self.first + Self.second)

        #expect(script.count == 2)
        #expect(script.remainingCharacters(from: 0) == Self.first.count + Self.second.count)
        #expect(script.remainingCharacters(from: 1) == Self.second.count)
        #expect(script.remainingCharacters(from: 2) == 0)
    }

    @Test func preservesEnglishSentenceSpacingAcrossLines() {
        let input = "This sentence is long enough to stand alone. The next sentence must not attach to it."
        let noMerge = TTSChunkingPolicy(maxChars: 400, softMaxChars: 300, minMergeChars: 0)

        let script = ReadAloudScript(text: input, policy: noMerge)

        #expect(script.count == 2)
        #expect(script.lines.map(\.text).joined() == input)
        #expect(script[1]?.text.hasPrefix(" ") == true)
    }

    @Test func preservesMixedLanguageSentenceSpacingAcrossLines() {
        let input = "This English sentence remains separate. 接下来这一句使用中文，而且同样保持原来的句间空格。"
        let noMerge = TTSChunkingPolicy(maxChars: 400, softMaxChars: 300, minMergeChars: 0)

        let script = ReadAloudScript(text: input, policy: noMerge)

        #expect(script.count == 2)
        #expect(script.lines.map(\.text).joined() == input)
        #expect(script[1]?.text == " 接下来这一句使用中文，而且同样保持原来的句间空格。")
    }
}

/// Line boundaries come from measured audio, so the highlight cannot drift onto a wrong
/// sentence however long the document runs.
struct ReadAloudLineTimelineTests {
    private func timeline(_ durations: [(Int, TimeInterval)]) -> ReadAloudLineTimeline {
        var t = ReadAloudLineTimeline()
        for (line, duration) in durations { t.append(line: line, duration: duration) }
        return t
    }

    @Test func laysLinesEndToEnd() {
        let t = timeline([(0, 2), (1, 3)])

        #expect(t.entries.map(\.start) == [0, 2])
        #expect(t.bufferedDuration == 5)
        #expect(t.start(ofLine: 1) == 2)
    }

    @Test func resolvesTheSoundingLine() {
        let t = timeline([(0, 2), (1, 3), (2, 1)])

        #expect(t.activeLine(at: 0) == 0)
        #expect(t.activeLine(at: 1.9) == 0)
        #expect(t.activeLine(at: 2) == 1)
        #expect(t.activeLine(at: 4.9) == 1)
        #expect(t.activeLine(at: 5) == 2)
    }

    /// Past the queued audio the highlight rests on the last line rather than blanking —
    /// the tail is still sounding while the pipeline synthesizes the next one.
    @Test func clampsPastTheEndToTheLastLine() {
        let t = timeline([(0, 2), (1, 3)])

        #expect(t.activeLine(at: 99) == 1)
        #expect(t.progress(at: 99) == 1)
    }

    @Test func emptyTimelineHasNoActiveLine() {
        #expect(ReadAloudLineTimeline().activeLine(at: 1) == nil)
        #expect(ReadAloudLineTimeline().bufferedDuration == 0)
    }

    @Test func progressIsFractionalWithinTheActiveLine() {
        let t = timeline([(0, 2), (1, 4)])

        #expect(t.progress(at: 1) == 0.5)
        #expect(t.progress(at: 4) == 0.5)   // 2s into the 4s line
    }

    /// A zero-duration entry would make its line unreachable and stall the highlight on the
    /// previous one, so the timeline refuses it.
    @Test func dropsNonPositiveDurations() {
        var t = ReadAloudLineTimeline()
        t.append(line: 0, duration: 0)
        t.append(line: 1, duration: -1)
        t.append(line: 2, duration: .nan)

        #expect(t.isEmpty)
    }

    /// The timeline is rebased on every restart (rate change, voice change, jump), so a reset
    /// has to put the next line back at offset zero.
    @Test func resetRebasesToZero() {
        var t = timeline([(0, 2), (1, 3)])
        t.reset()
        t.append(line: 7, duration: 1)

        #expect(t.start(ofLine: 7) == 0)
        #expect(t.activeLine(at: 0.5) == 7)
    }
}
