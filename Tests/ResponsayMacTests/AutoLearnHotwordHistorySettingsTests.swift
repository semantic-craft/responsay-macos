import XCTest
import ResponsayCore
@testable import ResponsayMac

final class AutoLearnHotwordHistorySettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "test.autoLearnHotwordHistorySettings"

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

    func testConfirmationPolicyDefaultsToHighConfidenceAutoAdd() {
        XCTAssertEqual(
            AutoLearnHotwordHistorySettings.confirmationPolicy(defaults: defaults),
            .autoAddHighConfidence)
    }

    func testConfirmationPolicyRoundTrips() {
        AutoLearnHotwordHistorySettings.setConfirmationPolicy(.confirmEveryTime, defaults: defaults)

        XCTAssertEqual(
            AutoLearnHotwordHistorySettings.confirmationPolicy(defaults: defaults),
            .confirmEveryTime)
    }

    func testLearningHistoryRoundTrips() {
        let record = HotwordLearningRecord(
            term: "Responsay",
            source: .cloudBYOK,
            status: .added,
            reason: "云端候选",
            learnedAt: Date(timeIntervalSince1970: 10))

        XCTAssertTrue(AutoLearnHotwordHistorySettings.save([record], defaults: defaults))

        XCTAssertEqual(AutoLearnHotwordHistorySettings.records(defaults: defaults), [record])
    }

    func testAppendPersistsCorrectionEventFieldsAcrossReadback() {
        let proposal = HotwordCandidateProposal(
            term: "Claude Code",
            source: .localRules,
            confidence: 0.9,
            reason: "用户把「Cloud Xcode」改成「Claude Code」",
            sourceTerm: "Cloud Xcode",
            appName: "com.apple.TextEdit",
            windowTitle: "Untitled")

        XCTAssertTrue(AutoLearnHotwordHistorySettings.append(
            proposal,
            status: .added,
            at: Date(timeIntervalSince1970: 12),
            defaults: defaults))

        let record = AutoLearnHotwordHistorySettings.records(defaults: defaults).first
        XCTAssertEqual(record?.term, "Claude Code")
        XCTAssertEqual(record?.sourceTerm, "Cloud Xcode")
        XCTAssertEqual(record?.appName, "com.apple.TextEdit")
        XCTAssertEqual(record?.windowTitle, "Untitled")
        XCTAssertEqual(record?.status, .added)
        XCTAssertEqual(record?.learnedAt, Date(timeIntervalSince1970: 12))
    }

    func testMarkAddedPromotesPendingRecord() {
        let record = HotwordLearningRecord(
            term: "Responsay",
            source: .localRules,
            status: .pending,
            reason: "待确认",
            learnedAt: Date(timeIntervalSince1970: 10))
        XCTAssertTrue(AutoLearnHotwordHistorySettings.save([record], defaults: defaults))

        AutoLearnHotwordHistorySettings.markAdded(
            term: "Responsay",
            at: Date(timeIntervalSince1970: 20),
            defaults: defaults)

        let updated = AutoLearnHotwordHistorySettings.records(defaults: defaults).first
        XCTAssertEqual(updated?.status, .added)
        XCTAssertEqual(updated?.learnedAt, Date(timeIntervalSince1970: 20))
    }
}
