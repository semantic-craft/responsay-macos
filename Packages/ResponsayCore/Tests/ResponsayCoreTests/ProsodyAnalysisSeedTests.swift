import Testing
import Foundation
@testable import ResponsayCore

/// 125 — `ProsodyAnalysis.followReadSeed(from:)` builds a minimal, honest analysis from an
/// arbitrary English sentence so the follow-read loop can start from selected/rewritten text
/// (not only the canned samples). It renders words without inventing stress/tone analysis;
/// only the sentence-terminal tone is inferred. Full prosody stays the analyzer's job (143).
struct ProsodyAnalysisSeedTests {

    @Test func tokenizesWordsPreservingOrderAndText() {
        let seed = ProsodyAnalysis.followReadSeed(from: "I want to know")
        let words = seed.thoughtGroups.flatMap(\.words).map(\.text)
        #expect(words == ["I", "want", "to", "know"])
        #expect(seed.text == "I want to know")
    }

    @Test func allWordsLiveInASingleThoughtGroup() {
        let seed = ProsodyAnalysis.followReadSeed(from: "one two three")
        #expect(seed.thoughtGroups.count == 1)
        #expect(seed.thoughtGroups.first?.words.count == 3)
    }

    @Test func metadataIsNeutralAndWordsUnanalyzed() {
        let seed = ProsodyAnalysis.followReadSeed(from: "Keep it simple")
        #expect(seed.isGeneratedExample == false)
        #expect(seed.sourceWord == nil)
        #expect(seed.ipa.isEmpty)
        #expect(seed.notes == nil)
        for word in seed.thoughtGroups.flatMap(\.words) {
            #expect(word.stressed == false)
            #expect(word.nuclear == false)
            #expect(word.stressIndex == nil)
            #expect(word.ipa == nil)
            #expect(word.linkToNext == nil)
            #expect(word.syllables == [word.text])
        }
    }

    @Test func questionInfersRisingTone() {
        let seed = ProsodyAnalysis.followReadSeed(from: "Can you finish this today?")
        #expect(seed.thoughtGroups.first?.tone == .rise)
    }

    @Test func statementInfersFallingTone() {
        let seed = ProsodyAnalysis.followReadSeed(from: "I'll send it tonight.")
        #expect(seed.thoughtGroups.first?.tone == .fall)
    }

    @Test func trimsAndCollapsesSurroundingWhitespace() {
        let seed = ProsodyAnalysis.followReadSeed(from: "  hello   world  ")
        #expect(seed.text == "hello world")
        #expect(seed.thoughtGroups.flatMap(\.words).map(\.text) == ["hello", "world"])
    }

    @Test func emptyInputYieldsNoWords() {
        let seed = ProsodyAnalysis.followReadSeed(from: "   ")
        #expect(seed.text.isEmpty)
        #expect(seed.thoughtGroups.flatMap(\.words).isEmpty)
    }
}
