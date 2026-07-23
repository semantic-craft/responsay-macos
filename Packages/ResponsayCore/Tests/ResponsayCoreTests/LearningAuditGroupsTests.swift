import Testing
import Foundation
@testable import ResponsayCore

@Suite struct LearningAuditGroupsTests {
    private let deterministic = HotwordSensitivityClassifier(
        gazetteer: ["民法典"], useNamedEntityRecognition: false)

    private func record(
        _ term: String,
        _ status: HotwordLearningRecordStatus,
        at t: TimeInterval,
        confidence: Double? = nil
    ) -> HotwordLearningRecord {
        HotwordLearningRecord(
            term: term, source: .localRules, status: status, reason: "",
            learnedAt: Date(timeIntervalSince1970: t), confidence: confidence)
    }

    @Test func groupsRecordsByStatusPreservingOrder() {
        let groups = LearningAuditGroups(records: [
            record("C", .pending, at: 3),
            record("B", .added, at: 2),
            record("A", .pending, at: 1),
        ], classifier: deterministic)

        #expect(groups.pending.map(\.term) == ["C", "A"])
        #expect(groups.added.map(\.term) == ["B"])
        #expect(groups.ignored.isEmpty)
        #expect(groups.undone.isEmpty)
    }

    @Test func rowCarriesDerivedSensitivityReason() throws {
        let groups = LearningAuditGroups(records: [
            record("民法典", .added, at: 2),
            record("报告", .added, at: 1),
        ], classifier: deterministic)

        let legal = try #require(groups.added.first { $0.term == "民法典" })
        let ordinary = try #require(groups.added.first { $0.term == "报告" })
        #expect(legal.sensitivityReason == .legalGazetteer)
        #expect(ordinary.sensitivityReason == nil)
    }
}
