import XCTest
import ResponsayCore
@testable import ResponsayMac

final class HistoryRetentionCleanupTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "test.historyRetentionCleanup"

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

    func testPolicyUsesAdvertisedValuesAndDefaultsUnknownValuesToThirtyDays() {
        XCTAssertEqual(HistoryRetentionPeriod(storedValue: "never"), .never)
        XCTAssertEqual(HistoryRetentionPeriod(storedValue: "7"), .days(7))
        XCTAssertEqual(HistoryRetentionPeriod(storedValue: "30"), .days(30))
        XCTAssertEqual(HistoryRetentionPeriod(storedValue: "90"), .days(90))
        XCTAssertEqual(HistoryRetentionPeriod(storedValue: "unexpected"), .days(30))
    }

    @MainActor
    func testCaptureCleanupExpiresTheExactBoundaryAndPreservesValidAndSessionData() throws {
        defaults.set("7", forKey: HistoryRetentionSettings.cleanupKey)
        defaults.set("keep-me", forKey: "unrelated.setting")
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let cutoff = now.addingTimeInterval(-7 * 24 * 60 * 60)
        let store = FileCaptureStore(fileURL: temporaryCaptureURL())
        let expiredBeforeBoundary = capture(id: "11111111-1111-1111-1111-111111111111", at: cutoff.addingTimeInterval(-1))
        let expiredAtBoundary = capture(id: "22222222-2222-2222-2222-222222222222", at: cutoff)
        let valid = capture(id: "33333333-3333-3333-3333-333333333333", at: cutoff.addingTimeInterval(1))
        try store.save(expiredBeforeBoundary)
        try store.save(expiredAtBoundary)
        try store.save(valid)

        let activeContext = RecentASRContextSessionStore()
        activeContext.record("current in-memory context", scope: "com.example.active")

        let removed = try HistoryRetentionCleanup.pruneCaptureRecords(
            in: store,
            defaults: defaults,
            now: now)

        XCTAssertEqual(removed, 2)
        XCTAssertEqual(try store.recent(10).map(\.id), [valid.id])
        XCTAssertEqual(defaults.string(forKey: "unrelated.setting"), "keep-me")
        XCTAssertEqual(activeContext.context(for: "com.example.active"), ["current in-memory context"])
    }

    func testNeverPolicyLeavesEveryCaptureUntouched() throws {
        defaults.set("never", forKey: HistoryRetentionSettings.cleanupKey)
        let store = FileCaptureStore(fileURL: temporaryCaptureURL())
        let old = capture(id: "44444444-4444-4444-4444-444444444444", at: .distantPast)
        try store.save(old)

        XCTAssertEqual(
            try HistoryRetentionCleanup.pruneCaptureRecords(
                in: store,
                defaults: defaults,
                now: Date(timeIntervalSince1970: 2_000_000_000)),
            0)
        XCTAssertEqual(try store.recent(10).map(\.id), [old.id])
    }

    func testLearningHistoryReadPrunesByTheSameBoundaryWithoutDeletingDictionaryTerms() {
        defaults.set("30", forKey: HistoryRetentionSettings.cleanupKey)
        defaults.set("keep-me", forKey: "unrelated.setting")
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let cutoff = now.addingTimeInterval(-30 * 24 * 60 * 60)
        let expired = learningRecord(
            id: "55555555-5555-5555-5555-555555555555",
            term: "Expired ledger event",
            at: cutoff)
        let valid = learningRecord(
            id: "66666666-6666-6666-6666-666666666666",
            term: "Valid ledger event",
            at: cutoff.addingTimeInterval(1))
        XCTAssertTrue(AutoLearnHotwordHistorySettings.save([valid, expired], defaults: defaults))
        XCTAssertTrue(ContextHotwordSettings.addAuto(
            "DurableTerm",
            learnedAt: cutoff.addingTimeInterval(-1),
            defaults: defaults))

        let records = AutoLearnHotwordHistorySettings.records(defaults: defaults, now: now)

        XCTAssertEqual(records, [valid])
        XCTAssertEqual(AutoLearnHotwordHistorySettings.records(defaults: defaults, now: now), [valid])
        XCTAssertEqual(ContextHotwordSettings.autoHotwords(defaults: defaults), ["DurableTerm"])
        XCTAssertEqual(defaults.string(forKey: "unrelated.setting"), "keep-me")
    }

    private func temporaryCaptureURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("captures.json")
    }

    private func capture(id: String, at date: Date) -> CaptureItem {
        CaptureItem(
            id: UUID(uuidString: id)!,
            createdAt: date,
            sourceText: "synthetic capture",
            language: "en-US",
            idiomatic: "Synthetic capture.",
            reasons: [])
    }

    private func learningRecord(id: String, term: String, at date: Date) -> HotwordLearningRecord {
        HotwordLearningRecord(
            id: UUID(uuidString: id)!,
            term: term,
            source: .localRules,
            status: .added,
            reason: "synthetic test record",
            learnedAt: date)
    }
}
