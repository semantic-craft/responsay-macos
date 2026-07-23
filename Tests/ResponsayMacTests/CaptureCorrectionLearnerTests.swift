import XCTest
import ResponsayCore
@testable import ResponsayMac

/// 518 — the capsule「纠正并学习」confirm action: one explicit correction writes BOTH biasing ends
/// (manual dictionary + learned alias) so the same mishear is deterministically repaired next time.
final class CaptureCorrectionLearnerTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "test.captureCorrectionLearner"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    func testLearnWritesDictionaryAliasRecordAndNotifies() {
        var notified: [String] = []
        let outcome = CaptureCorrectionLearner.learn(
            wrong: "Metapocalypse", correct: "Matt Pocock",
            defaults: defaults, notify: { notified.append($0) })

        XCTAssertEqual(outcome, .learned)
        XCTAssertTrue(ContextHotwordSettings.hotwords(defaults: defaults).contains("Matt Pocock"))
        XCTAssertEqual(
            ContextHotwordSettings.biasingSets(defaults: defaults).learnedAliases["Metapocalypse"],
            "Matt Pocock")
        let record = AutoLearnHotwordHistorySettings.records(defaults: defaults).first
        XCTAssertEqual(record?.term, "Matt Pocock")
        XCTAssertEqual(record?.sourceTerm, "Metapocalypse")
        XCTAssertEqual(record?.status, .added)
        XCTAssertEqual(record?.source, .manual)   // round-trips through the Codable ledger
        XCTAssertEqual(record?.reason, "用户手动纠正")
        XCTAssertEqual(notified, ["Matt Pocock"])
    }

    func testEnforceRepairsTheSameMishearDeterministically() {
        CaptureCorrectionLearner.learn(
            wrong: "Metapocalypse", correct: "Matt Pocock", defaults: defaults, notify: { _ in })

        let repaired = ContextHotwordSettings.biasingSets(defaults: defaults)
            .enforce("我说的是 Metapocalypse 的技能").text
        XCTAssertTrue(repaired.contains("Matt Pocock"))
        XCTAssertFalse(repaired.contains("Metapocalypse"))
    }

    func testDeletingTheTermFromDictionaryPageRetiresTheAlias() {
        // 走设置词典页的真实删除路径(store.delete):除移出词典外还要给 ledger 记录打墓碑——
        // #505 的 lexical profile 车道会从历史独立回灌 alias,光 removeManual 退不掉它。
        CaptureCorrectionLearner.learn(
            wrong: "Metapocalypse", correct: "Matt Pocock", defaults: defaults, notify: { _ in })
        UserDictionarySettingsStore(defaults: defaults)
            .delete(HotwordTerm(text: "Matt Pocock", source: .manual))

        let sets = ContextHotwordSettings.biasingSets(defaults: defaults)
        XCTAssertNil(sets.learnedAliases["Metapocalypse"])
        XCTAssertTrue(sets.enforce("我说的是 Metapocalypse").text.contains("Metapocalypse"))
    }

    func testGuardsRejectEmptyAndEqualInputsWithoutDirtyState() {
        var notified: [String] = []
        XCTAssertNotEqual(CaptureCorrectionLearner.learn(
            wrong: "  ", correct: "Matt Pocock", defaults: defaults, notify: { notified.append($0) }), .learned)
        XCTAssertNotEqual(CaptureCorrectionLearner.learn(
            wrong: "Metapocalypse", correct: "", defaults: defaults, notify: { notified.append($0) }), .learned)
        XCTAssertNotEqual(CaptureCorrectionLearner.learn(
            wrong: "Matt Pocock", correct: "Matt Pocock", defaults: defaults, notify: { notified.append($0) }), .learned)

        XCTAssertTrue(ContextHotwordSettings.hotwords(defaults: defaults).isEmpty)
        XCTAssertTrue(AutoLearnHotwordHistorySettings.records(defaults: defaults).isEmpty)
        XCTAssertTrue(notified.isEmpty)
    }

    func testRepeatConfirmIsIdempotent() {
        for _ in 0..<2 {
            XCTAssertEqual(CaptureCorrectionLearner.learn(
                wrong: "Metapocalypse", correct: "Matt Pocock", defaults: defaults, notify: { _ in }), .learned)
        }
        XCTAssertEqual(
            ContextHotwordSettings.hotwords(defaults: defaults).filter { $0 == "Matt Pocock" }.count, 1)
        let pairRecords = AutoLearnHotwordHistorySettings.records(defaults: defaults)
            .filter { $0.term == "Matt Pocock" && $0.sourceTerm == "Metapocalypse" }
        XCTAssertEqual(pairRecords.count, 1)
    }

    func testCorrectAlreadyInDictionaryStillLearnsTheAlias() {
        XCTAssertTrue(ContextHotwordSettings.addManual("Matt Pocock", defaults: defaults))

        XCTAssertEqual(CaptureCorrectionLearner.learn(
            wrong: "Metapocalypse", correct: "Matt Pocock", defaults: defaults, notify: { _ in }), .learned)
        XCTAssertEqual(
            ContextHotwordSettings.hotwords(defaults: defaults).filter { $0 == "Matt Pocock" }.count, 1)
        XCTAssertEqual(
            ContextHotwordSettings.biasingSets(defaults: defaults).learnedAliases["Metapocalypse"],
            "Matt Pocock")
    }
}
