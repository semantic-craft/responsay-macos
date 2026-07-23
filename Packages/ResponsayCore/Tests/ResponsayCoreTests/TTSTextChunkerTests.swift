import Testing
import Foundation
@testable import ResponsayCore

/// 133 — TTS text chunking policy.
/// Verification: zh/en mixed; abbreviations & decimals not mis-split; over-long split.
struct TTSTextChunkerTests {
    private let chunker = TTSTextChunker()
    /// No-merge policy so sentence boundaries are observable directly.
    private let noMerge = TTSChunkingPolicy(maxChars: 400, softMaxChars: 300, minMergeChars: 0)

    @Test func sentenceBoundarySplit_english() {
        let chunks = chunker.chunk("Hello world. How are you? I am fine.", policy: noMerge)
        #expect(chunks.map(\.text) == ["Hello world.", "How are you?", "I am fine."])
    }

    @Test func mixedZhEn_splitsAtEachBoundary() {
        let chunks = chunker.chunk("我今天去了公司。Then I came home.", policy: noMerge)
        #expect(chunks.count == 2)
        #expect(chunks[0].text == "我今天去了公司。")
        #expect(chunks[1].text == "Then I came home.")
    }

    @Test func paragraphFirst() {
        let chunks = chunker.chunk("First para here.\n\nSecond para here.", policy: noMerge)
        #expect(chunks.map(\.text) == ["First para here.", "Second para here."])
    }

    @Test func abbreviationsAndDecimals_notMisSplit() {
        let text = "Dr. Smith paid $3.50 to the U.S. team. Done."
        let chunks = chunker.chunk(text, policy: noMerge)
        #expect(chunks.count == 2)
        #expect(chunks[0].text == "Dr. Smith paid $3.50 to the U.S. team.")
        #expect(chunks[1].text == "Done.")
    }

    @Test func overLongSentence_softSplitsUnderMax() {
        // One long comma-separated sentence, no terminal boundary.
        let clause = Array(repeating: "这是一个很长的从句", count: 30).joined(separator: "，")
        let policy = TTSChunkingPolicy(maxChars: 80, softMaxChars: 60, minMergeChars: 0)
        let chunks = chunker.chunk(clause, policy: policy)
        #expect(chunks.count > 1)
        #expect(chunks.allSatisfy { $0.text.count <= policy.maxChars })
    }

    @Test func smallBlocksMerged() {
        // Three tiny sentences; a merge policy folds them together.
        let policy = TTSChunkingPolicy(maxChars: 200, softMaxChars: 160, minMergeChars: 30)
        let chunks = chunker.chunk("Hi. Ok. Done.", policy: policy)
        #expect(chunks.count == 1)
        #expect(chunks[0].text.contains("Hi."))
        #expect(chunks[0].text.contains("Done."))
    }

    @Test func everyChunkHasUniqueSegmentID_andOrder() {
        let chunks = chunker.chunk("One. Two. Three.", policy: noMerge)
        #expect(Set(chunks.map(\.segmentID)).count == chunks.count)
        #expect(chunks.map(\.order) == Array(0..<chunks.count))
    }

    @Test func emptyText_yieldsNoChunks() {
        #expect(chunker.chunk("   \n\n  ", policy: noMerge).isEmpty)
    }

    @Test func noTerminalPunctuation_isOneChunk() {
        let chunks = chunker.chunk("just a fragment without an end", policy: noMerge)
        #expect(chunks.count == 1)
    }
}
