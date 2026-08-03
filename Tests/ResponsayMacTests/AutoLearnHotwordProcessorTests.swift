import XCTest
import ResponsayCore
@testable import ResponsayMac

@MainActor
final class AutoLearnHotwordProcessorTests: XCTestCase {
    func testLocalRulesAddsHighConfidenceCandidateAndRecordsHistory() async {
        var added: [HotwordCandidateProposal] = []
        var records: [(HotwordCandidateProposal, HotwordLearningRecordStatus)] = []
        let processor = AutoLearnHotwordProcessor(
            isEnabled: { true },
            mode: { .localRules },
            confirmationPolicy: { .autoAddHighConfidence },
            existingManualTerms: { [] },
            existingAutoTerms: { [] },
            addAuto: { proposal in added.append(proposal); return true },
            record: { proposal, status in records.append((proposal, status)); return true })

        let result = await processor.process(Self.context)

        XCTAssertEqual(result.addedTerms, ["个人信息处理者"])
        XCTAssertEqual(added.map(\.term), ["个人信息处理者"])
        XCTAssertEqual(records.map { "\($0.0.term):\($0.1.rawValue)" }, ["个人信息处理者:added"])
        XCTAssertEqual(records.first?.0.sourceTerm, "个人信息处理着")
        XCTAssertEqual(records.first?.0.appName, "Notes")
        XCTAssertEqual(records.first?.0.windowTitle, "论文草稿")
    }

    /// PRD §3 Tier 1: a specialized term (here a legal seed-gazetteer word) is both added and
    /// surfaced via the undo toast (`notifiedTerms`). Ordinary terms stay out of `notifiedTerms`
    /// (added silently) — covered deterministically at the decision layer.
    func testSpecializedTermSurfacesAToast() async {
        let processor = AutoLearnHotwordProcessor(
            isEnabled: { true },
            mode: { .localModel },
            confirmationPolicy: { .autoAddHighConfidence },
            existingManualTerms: { [] },
            existingAutoTerms: { [] },
            addAuto: { _ in true },
            record: { _, _ in true },
            localModelExtract: { _ in
                .init(candidates: [HotwordCandidateProposal(
                    term: "民法典", source: .localModel, confidence: 0.95, reason: "专名纠正")],
                    status: .ready)
            })

        let result = await processor.process(Self.context)

        XCTAssertEqual(result.addedTerms, ["民法典"])
        XCTAssertEqual(result.notifiedTerms, ["民法典"], "specialized term surfaces the undo toast")
    }

    func testDisabledProcessorDoesNothing() async {
        var called = false
        let processor = AutoLearnHotwordProcessor(
            isEnabled: { false },
            mode: { .localRules },
            confirmationPolicy: { .autoAddHighConfidence },
            existingManualTerms: { [] },
            existingAutoTerms: { [] },
            addAuto: { _ in called = true; return true },
            record: { _, _ in called = true; return true })

        let result = await processor.process(Self.context)

        XCTAssertTrue(result.addedTerms.isEmpty)
        XCTAssertFalse(called)
    }

    func testExplicitCorrectionLearningWorksWhileBroadAutoLearnIsDisabled() async {
        var added: [HotwordCandidateProposal] = []
        var statuses: [HotwordLearningRecordStatus] = []
        let processor = AutoLearnHotwordProcessor(
            isEnabled: { false },
            isExplicitCorrectionLearningEnabled: { true },
            mode: { .localRules },
            confirmationPolicy: { .confirmEveryTime },
            existingManualTerms: { [] },
            existingAutoTerms: { [] },
            addAuto: { proposal in added.append(proposal); return true },
            record: { _, status in statuses.append(status); return true })

        let result = await processor.process(HotwordCorrectionContext(
            insertedText: "I use matis every day.",
            userFinalText: "I use Metis every day.",
            appName: "com.apple.TextEdit",
            windowTitle: "Untitled"))

        XCTAssertEqual(result.addedTerms, ["Metis"])
        XCTAssertEqual(added.map(\.sourceTerm), ["matis"])
        XCTAssertEqual(statuses, [.added])
    }

    func testLocalModelFailureFallsBackToLocalRules() async {
        let processor = AutoLearnHotwordProcessor(
            isEnabled: { true },
            mode: { .localModel },
            confirmationPolicy: { .autoAddHighConfidence },
            existingManualTerms: { [] },
            existingAutoTerms: { [] },
            addAuto: { _ in true },
            record: { _, _ in true },
            localModelExtract: { _ in .init(candidates: [], status: .timedOut) })

        let result = await processor.process(Self.context)

        XCTAssertEqual(result.addedTerms, ["个人信息处理者"])
        XCTAssertEqual(result.extractionStatus, .ready)
    }

    func testProtectedAppDoesNotEnterLongTermLearning() async {
        var didRecord = false
        let processor = AutoLearnHotwordProcessor(
            isEnabled: { true },
            mode: { .localRules },
            confirmationPolicy: { .autoAddHighConfidence },
            existingManualTerms: { [] },
            existingAutoTerms: { [] },
            addAuto: { _ in true },
            record: { _, _ in didRecord = true; return true },
            longTermLearningRejection: { _ in .protectedApp })

        let result = await processor.process(HotwordCorrectionContext(
            insertedText: "Cloud Code",
            userFinalText: "Claude Code",
            appName: "Xcode",
            windowTitle: "main.swift"))

        XCTAssertTrue(result.addedTerms.isEmpty)
        XCTAssertFalse(didRecord)
    }

    func testConfirmEveryTimeRecordsPendingWithoutAdding() async {
        var added: [String] = []
        var statuses: [HotwordLearningRecordStatus] = []
        let processor = AutoLearnHotwordProcessor(
            isEnabled: { true },
            mode: { .localRules },
            confirmationPolicy: { .confirmEveryTime },
            existingManualTerms: { [] },
            existingAutoTerms: { [] },
            addAuto: { proposal in added.append(proposal.term); return true },
            record: { _, status in statuses.append(status); return true })

        let result = await processor.process(Self.context)

        XCTAssertTrue(result.addedTerms.isEmpty)
        XCTAssertTrue(added.isEmpty)
        XCTAssertEqual(statuses, [.pending])
    }

    func testRepeatedCorrectionReaddsUndoneTerm() async {
        var added: [String] = []
        var statuses: [HotwordLearningRecordStatus] = []
        let processor = AutoLearnHotwordProcessor(
            isEnabled: { true },
            mode: { .localRules },
            confirmationPolicy: { .autoAddHighConfidence },
            existingManualTerms: { [] },
            existingAutoTerms: { [] },
            addAuto: { proposal in added.append(proposal.term); return true },
            record: { _, status in statuses.append(status); return true },
            recentlyUndoneTerms: { ["Claude Code"] })

        let result = await processor.process(HotwordCorrectionContext(
            insertedText: "Cloud Xcode",
            userFinalText: "Claude Code",
            appName: nil,
            windowTitle: nil))

        XCTAssertEqual(result.addedTerms, ["Claude Code"])
        XCTAssertEqual(added, ["Claude Code"])
        XCTAssertEqual(statuses, [.added])
    }

    func testCloudCodeCorrectionAddsClaudeCodePhrase() async {
        var added: [String] = []
        var records: [(HotwordCandidateProposal, HotwordLearningRecordStatus)] = []
        let processor = AutoLearnHotwordProcessor(
            isEnabled: { true },
            mode: { .localRules },
            confirmationPolicy: { .autoAddHighConfidence },
            existingManualTerms: { [] },
            existingAutoTerms: { [] },
            addAuto: { proposal in added.append(proposal.term); return true },
            record: { proposal, status in records.append((proposal, status)); return true })

        let result = await processor.process(HotwordCorrectionContext(
            insertedText: "Cloud Code",
            userFinalText: "Claude Code",
            appName: nil,
            windowTitle: nil))

        XCTAssertEqual(result.addedTerms, ["Claude Code"])
        XCTAssertEqual(added, ["Claude Code"])
        XCTAssertEqual(records.map(\.1), [.added])
        XCTAssertEqual(records.first?.0.sourceTerm, "Cloud Code")
    }

    func testExplicitCorrectionToExistingTermRecordsAliasWithoutDuplicateAdd() async {
        var added: [String] = []
        var records: [(HotwordCandidateProposal, HotwordLearningRecordStatus)] = []
        let processor = AutoLearnHotwordProcessor(
            isEnabled: { true },
            mode: { .localRules },
            confirmationPolicy: { .autoAddHighConfidence },
            existingManualTerms: { ["Claude Code"] },
            existingAutoTerms: { [] },
            addAuto: { proposal in added.append(proposal.term); return false },
            record: { proposal, status in records.append((proposal, status)); return true })

        let result = await processor.process(HotwordCorrectionContext(
            insertedText: "Cloud Code",
            userFinalText: "Claude Code",
            appName: nil,
            windowTitle: nil))

        XCTAssertTrue(result.addedTerms.isEmpty)
        XCTAssertEqual(added, ["Claude Code"])
        XCTAssertEqual(records.map(\.1), [.added, .ignored])
        XCTAssertEqual(records.first?.0.sourceTerm, "Cloud Code")
    }

    func testRecordFailureSkipsAutoAdd() async {
        var didAdd = false
        let processor = AutoLearnHotwordProcessor(
            isEnabled: { true },
            mode: { .localRules },
            confirmationPolicy: { .autoAddHighConfidence },
            existingManualTerms: { [] },
            existingAutoTerms: { [] },
            addAuto: { _ in didAdd = true; return true },
            record: { _, _ in false })

        let result = await processor.process(Self.context)

        XCTAssertTrue(result.addedTerms.isEmpty)
        XCTAssertFalse(didAdd)
    }

    private static let context = HotwordCorrectionContext(
        insertedText: "个人信息处理着，原则",
        userFinalText: "个人信息处理者，原则",
        appName: "Notes",
        windowTitle: "论文草稿")
}
