import Testing
import Foundation
@testable import ResponsayCore

@Suite struct HotwordLearningHistoryTests {
    @Test func recordsOnlyCandidateMetadata() throws {
        let proposal = HotwordCandidateProposal(
            term: "沈砚秋",
            source: .cloudBYOK,
            confidence: 0.94,
            reason: "用户把人名改成该写法",
            sourceTerm: "沈燕秋",
            appName: "com.apple.TextEdit",
            windowTitle: "论文草稿")
        var history = HotwordLearningHistory()

        history.record(proposal, status: .added, at: Date(timeIntervalSince1970: 10))

        let record = try #require(history.records.first)
        #expect(record.term == "沈砚秋")
        #expect(record.source == .cloudBYOK)
        #expect(record.status == .added)
        #expect(record.reason == "用户把人名改成该写法")
        #expect(record.sourceTerm == "沈燕秋")
        #expect(record.appName == "com.apple.TextEdit")
        #expect(record.windowTitle == "论文草稿")

        let encoded = String(data: try JSONEncoder().encode(history.records), encoding: .utf8) ?? ""
        #expect(!encoded.contains("刚写入文本"))
        #expect(!encoded.contains("用户修改后"))
    }

    @Test func recordCapturesConfidenceFromProposal() {
        var history = HotwordLearningHistory()
        history.record(
            .init(term: "民法典", source: .cloudBYOK, confidence: 0.93, reason: "纠正"),
            status: .pending, at: Date(timeIntervalSince1970: 10))

        #expect(history.records.first?.confidence == 0.93)
    }

    @Test func legacyRecordWithoutConfidenceStillDecodes() throws {
        // A record persisted before 454 has no `confidence` key — it must decode (not wipe history).
        let legacyJSON = """
        [{"id":"00000000-0000-0000-0000-000000000001","term":"民法典","source":"cloudBYOK",\
        "status":"added","reason":"纠正","learnedAt":0}]
        """
        let records = try JSONDecoder().decode(
            [HotwordLearningRecord].self, from: Data(legacyJSON.utf8))

        #expect(records.first?.term == "民法典")
        #expect(records.first?.confidence == nil)
    }

    @Test func undoMarksLatestMatchingRecordWithoutRevivingTerm() {
        var history = HotwordLearningHistory(records: [
            HotwordLearningRecord(
                term: "Responsay",
                source: .localRules,
                status: .added,
                reason: "用户纠正",
                learnedAt: Date(timeIntervalSince1970: 10))
        ])

        history.markUndone(term: "Responsay", at: Date(timeIntervalSince1970: 20))

        #expect(history.records.first?.status == .undone)
        #expect(history.records.first?.learnedAt == Date(timeIntervalSince1970: 20))
    }

    @Test func confirmMarksPendingRecordAsAdded() {
        var history = HotwordLearningHistory(records: [
            HotwordLearningRecord(
                term: "Responsay",
                source: .localRules,
                status: .pending,
                reason: "用户确认",
                learnedAt: Date(timeIntervalSince1970: 10))
        ])

        history.markAdded(term: "Responsay", at: Date(timeIntervalSince1970: 30))

        #expect(history.records.first?.status == .added)
        #expect(history.records.first?.learnedAt == Date(timeIntervalSince1970: 30))
    }

    @Test func confirmPrefersPendingRecordOverOlderMatches() throws {
        var history = HotwordLearningHistory(records: [
            HotwordLearningRecord(
                term: "Responsay",
                source: .localRules,
                status: .ignored,
                reason: "旧记录",
                learnedAt: Date(timeIntervalSince1970: 5)),
            HotwordLearningRecord(
                term: "Responsay",
                source: .cloudBYOK,
                status: .pending,
                reason: "待确认",
                learnedAt: Date(timeIntervalSince1970: 10))
        ])

        history.markAdded(term: "Responsay", at: Date(timeIntervalSince1970: 40))

        let ignored = try #require(history.records.first)
        let confirmed = try #require(history.records.dropFirst().first)
        #expect(ignored.status == .ignored)
        #expect(confirmed.status == .added)
        #expect(confirmed.learnedAt == Date(timeIntervalSince1970: 40))
    }

    @Test func newestRecordsStayFirstAndLimited() {
        var history = HotwordLearningHistory(limit: 2)

        history.record(.init(term: "A", source: .localRules, confidence: 0.9, reason: "1"), status: .added, at: Date(timeIntervalSince1970: 1))
        history.record(.init(term: "B", source: .localModel, confidence: 0.9, reason: "2"), status: .ignored, at: Date(timeIntervalSince1970: 2))
        history.record(.init(term: "C", source: .cloudBYOK, confidence: 0.9, reason: "3"), status: .pending, at: Date(timeIntervalSince1970: 3))

        #expect(history.records.map(\.term) == ["C", "B"])
    }

    // 445 — tombstone derivation.

    @Test func undoneTermIsTombstoned() {
        var history = HotwordLearningHistory()
        history.record(.init(term: "Responsay", source: .localRules, confidence: 0.9, reason: "纠正"), status: .added, at: Date(timeIntervalSince1970: 10))
        history.markUndone(term: "Responsay", at: Date(timeIntervalSince1970: 20))

        #expect(history.tombstonedTerms() == ["Responsay"])
    }

    @Test func reAddedAfterUndoClearsTheTombstone() {
        var history = HotwordLearningHistory()
        history.record(.init(term: "Responsay", source: .localRules, confidence: 0.9, reason: "纠正"), status: .added, at: Date(timeIntervalSince1970: 10))
        history.markUndone(term: "Responsay", at: Date(timeIntervalSince1970: 20))
        // A newer .added (e.g. confirmed again) outranks the undo.
        history.record(.init(term: "Responsay", source: .localRules, confidence: 0.9, reason: "再次纠正"), status: .added, at: Date(timeIntervalSince1970: 30))

        #expect(history.tombstonedTerms().isEmpty)
    }

    @Test func addedCorrectionBuildsLearnedAlias() {
        var history = HotwordLearningHistory()
        history.record(
            .init(
                term: "Zotero",
                source: .localRules,
                confidence: 0.92,
                reason: "用户纠正",
                sourceTerm: "zero"),
            status: .added,
            at: Date(timeIntervalSince1970: 10))

        #expect(history.learnedAliases() == ["zero": "Zotero"])
    }

    @Test func replayLearnedAliasMatchesLocally() {
        var history = HotwordLearningHistory()
        history.record(
            .init(
                term: "Claude Code",
                source: .localRules,
                confidence: 0.92,
                reason: "用户纠正",
                sourceTerm: "Cloud Code"),
            status: .added,
            at: Date(timeIntervalSince1970: 10))

        let replay = history.replayLearnedAlias(in: "I use Cloud Code every day")

        #expect(replay.status == .matched)
        #expect(replay.outputText == "I use Claude Code every day")
    }

    @Test func replayLearnedAliasExplainsTombstone() {
        var history = HotwordLearningHistory()
        history.record(
            .init(
                term: "Claude Code",
                source: .localRules,
                confidence: 0.92,
                reason: "用户纠正",
                sourceTerm: "Cloud Code"),
            status: .added,
            at: Date(timeIntervalSince1970: 10))
        history.markUndone(term: "Claude Code", at: Date(timeIntervalSince1970: 20))

        let replay = history.replayLearnedAlias(in: "Cloud Code")

        #expect(replay.status == .tombstoned)
    }

    @Test func replayLearnedAliasExplainsPendingCandidate() {
        var history = HotwordLearningHistory()
        history.record(
            .init(
                term: "Claude Code",
                source: .localRules,
                confidence: 0.7,
                reason: "待确认",
                sourceTerm: "Cloud Code"),
            status: .pending,
            at: Date(timeIntervalSince1970: 10))

        let replay = history.replayLearnedAlias(in: "Cloud Code")

        #expect(replay.status == .lowConfidence)
    }

    @Test func replayLearnedAliasExplainsProtectedContext() {
        let history = HotwordLearningHistory()

        let replay = history.replayLearnedAlias(in: "Cloud Code", protectedContext: true)

        #expect(replay.status == .protectedContext)
    }

    @Test func undoneCorrectionDoesNotBuildLearnedAlias() {
        var history = HotwordLearningHistory()
        history.record(
            .init(
                term: "Zotero",
                source: .localRules,
                confidence: 0.92,
                reason: "用户纠正",
                sourceTerm: "zero"),
            status: .added,
            at: Date(timeIntervalSince1970: 10))
        history.markUndone(term: "Zotero", at: Date(timeIntervalSince1970: 20))

        #expect(history.learnedAliases().isEmpty)
    }

    @Test func ignoredReattemptKeepsTheTombstone() {
        var history = HotwordLearningHistory()
        history.record(.init(term: "Responsay", source: .localRules, confidence: 0.9, reason: "纠正"), status: .added, at: Date(timeIntervalSince1970: 10))
        history.markUndone(term: "Responsay", at: Date(timeIntervalSince1970: 20))
        // A suppressed re-attempt records .ignored — it must NOT revive the term.
        history.record(.init(term: "Responsay", source: .localRules, confidence: 0.9, reason: "已撤销"), status: .ignored, at: Date(timeIntervalSince1970: 30))

        #expect(history.tombstonedTerms() == ["Responsay"])
    }

    @Test func neverUndoneTermIsNotTombstoned() {
        var history = HotwordLearningHistory()
        history.record(.init(term: "CLSCI", source: .localRules, confidence: 0.9, reason: "纠正"), status: .added, at: Date(timeIntervalSince1970: 10))

        #expect(history.tombstonedTerms().isEmpty)
    }
}
