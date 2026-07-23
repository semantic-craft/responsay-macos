import Testing
@testable import ResponsayCore

@Suite struct RuleBasedHotwordCandidateExtractorTests {
    @Test func nearMissEnglishPhraseIsLearned() async throws {
        let candidates = try await RuleBasedHotwordCandidateExtractor().extract(HotwordCorrectionContext(
            insertedText: "我最近在用 Cloud Xcode 写代码。",
            userFinalText: "我最近在用 Claude Code 写代码。",
            appName: "TextEdit",
            windowTitle: "Untitled"))

        #expect(candidates.map(\.term) == ["Claude Code"])
        #expect(candidates.first?.sourceTerm == "Cloud Xcode")
        #expect(candidates.first?.appName == "TextEdit")
        #expect(candidates.first?.windowTitle == "Untitled")
    }

    @Test func plainEnglishWordCorrectionIsLearnedForConfirmation() async throws {
        let candidates = try await RuleBasedHotwordCandidateExtractor().extract(HotwordCorrectionContext(
            insertedText: "I use cloud every day.",
            userFinalText: "I use Claude every day.",
            appName: "TextEdit",
            windowTitle: "Untitled"))

        #expect(candidates.map(\.term) == ["Claude"])
        // A plain word is a candidate but below the auto-add band, so it lands in 待确认, not the
        // live dictionary — the user approves it before it can bias recognition.
        let confidence = try #require(candidates.first?.confidence)
        #expect(confidence < HotwordLearningDecisionEngine.defaultHighConfidenceThreshold)
        #expect(confidence >= HotwordLearningDecisionEngine.defaultMidConfidenceThreshold)
    }

    @Test func ordinaryRewriteIsNotAutoLearned() async throws {
        let candidates = try await RuleBasedHotwordCandidateExtractor().extract(HotwordCorrectionContext(
            insertedText: "I will ship the draft today.",
            userFinalText: "I will rewrite the section today.",
            appName: "TextEdit",
            windowTitle: "Untitled"))

        #expect(candidates.isEmpty)
    }

    @Test func boundaryPunctuationOnlyChangeIsNotAutoLearned() async throws {
        let candidates = try await RuleBasedHotwordCandidateExtractor().extract(HotwordCorrectionContext(
            insertedText: "I USE CLOUD Xcode EVERY DAY。",
            userFinalText: "I USE Claude Code EVERY DAY.",
            appName: "TextEdit",
            windowTitle: "Untitled"))

        #expect(candidates.map(\.term) == ["Claude Code"])
        #expect(candidates.first?.sourceTerm == "CLOUD Xcode")
    }

    @Test func shortPartialFragmentIsNotAutoLearned() async throws {
        let candidates = try await RuleBasedHotwordCandidateExtractor().extract(HotwordCorrectionContext(
            insertedText: "I used Cloud today.",
            userFinalText: "I used Clou today.",
            appName: "TextEdit",
            windowTitle: "Untitled"))

        #expect(candidates.isEmpty)
    }

    @Test func phoneticCodeLikeNameIsLearned() async throws {
        let candidates = try await RuleBasedHotwordCandidateExtractor().extract(HotwordCorrectionContext(
            insertedText: "Open current note.",
            userFinalText: "Open KairoNote.",
            appName: "TextEdit",
            windowTitle: "Untitled"))

        #expect(candidates.map(\.term) == ["KairoNote"])
        #expect(candidates.first?.sourceTerm == "current note")
    }

    @Test func alternateNearSoundCodeLikeNameIsLearned() async throws {
        let candidates = try await RuleBasedHotwordCandidateExtractor().extract(HotwordCorrectionContext(
            insertedText: "Open carol note.",
            userFinalText: "Open KairoNote.",
            appName: "TextEdit",
            windowTitle: "Untitled"))

        #expect(candidates.map(\.term) == ["KairoNote"])
        #expect(candidates.first?.sourceTerm == "carol note")
    }

    @Test func commandPhraseIsNotAutoLearnedAsCodeLikeName() async throws {
        let candidates = try await RuleBasedHotwordCandidateExtractor().extract(HotwordCorrectionContext(
            insertedText: "Create note.",
            userFinalText: "KairoNote.",
            appName: "TextEdit",
            windowTitle: "Untitled"))

        #expect(candidates.isEmpty)
    }

    @Test func mergedBrandNameIsLearned() async throws {
        let candidates = try await RuleBasedHotwordCandidateExtractor().extract(HotwordCorrectionContext(
            insertedText: "I use response say daily.",
            userFinalText: "I use Responsay daily.",
            appName: "TextEdit",
            windowTitle: "Untitled"))

        #expect(candidates.map(\.term) == ["Responsay"])
        #expect(candidates.first?.sourceTerm == "response say")
    }

    @Test func crossSentenceAppendBoundaryIsNotAutoLearned() async throws {
        let candidates = try await RuleBasedHotwordCandidateExtractor().extract(HotwordCorrectionContext(
            insertedText: "Open delta forge.Existing baseline line.",
            userFinalText: "Open DeltaForge. Existing baseline line.",
            appName: "TextEdit",
            windowTitle: "Untitled"))

        #expect(candidates.isEmpty)
    }
}
