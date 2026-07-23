import ResponsayCore
import XCTest
@testable import ResponsayMac

final class UserDictionarySettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "UserDictionarySettingsStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testManualAddPromotesExistingTermToFront() {
        let store = UserDictionarySettingsStore(defaults: defaults)

        XCTAssertTrue(store.addManual("Responsay"))
        XCTAssertTrue(store.addManual("CLSCI"))
        XCTAssertTrue(store.addManual("Responsay"))

        XCTAssertEqual(ContextHotwordSettings.hotwords(defaults: defaults), ["Responsay", "CLSCI"])
        XCTAssertEqual(store.store.userTermEntries.map(\.text), ["Responsay", "CLSCI"])
        XCTAssertEqual(store.hotwordsRaw, "Responsay\nCLSCI")
    }

    func testConfirmAndUndoAutoTermUpdateDictionaryMetadataAndHistory() {
        let date = Date(timeIntervalSince1970: 42)
        let store = UserDictionarySettingsStore(defaults: defaults, now: { date })
        let record = HotwordLearningRecord(
            term: "Qwen3-ASR",
            source: .localModel,
            status: .pending,
            reason: "本地模型识别为术语",
            learnedAt: Date(timeIntervalSince1970: 1))
        AutoLearnHotwordHistorySettings.save([record], defaults: defaults)

        XCTAssertTrue(store.confirmAuto(record))

        let entry = store.store.userTermEntries.first
        XCTAssertEqual(entry?.text, "Qwen3-ASR")
        XCTAssertEqual(entry?.source, .auto)
        XCTAssertEqual(entry?.learnedSource, .localModel)
        XCTAssertEqual(entry?.learnedAt, date)
        XCTAssertEqual(store.recentLearningRecords.first?.status, .added)
        XCTAssertEqual(store.recentLearningRecords.first?.learnedAt, date)

        store.undoAuto("Qwen3-ASR")

        XCTAssertEqual(ContextHotwordSettings.autoHotwords(defaults: defaults), [])
        XCTAssertNil(ContextHotwordSettings.autoMetadata(defaults: defaults)["Qwen3-ASR"])
        XCTAssertEqual(store.recentLearningRecords.first?.status, .undone)
        XCTAssertEqual(store.recentLearningRecords.first?.learnedAt, date)
    }

    func testRejectAutoTombstonesPendingTermWithoutAddingToDictionary() {
        let date = Date(timeIntervalSince1970: 42)
        let store = UserDictionarySettingsStore(defaults: defaults, now: { date })
        let record = HotwordLearningRecord(
            term: "缔约过失",
            source: .cloudBYOK,
            status: .pending,
            reason: "待确认",
            learnedAt: Date(timeIntervalSince1970: 1))
        AutoLearnHotwordHistorySettings.save([record], defaults: defaults)

        store.rejectAuto("缔约过失")

        XCTAssertEqual(ContextHotwordSettings.autoHotwords(defaults: defaults), [])
        XCTAssertEqual(store.recentLearningRecords.first?.status, .undone)
        XCTAssertTrue(
            HotwordLearningHistory(records: store.recentLearningRecords)
                .tombstonedTerms().contains("缔约过失"))
    }

    func testResetAutoLearningClearsAutoTermsAndHistoryKeepingManual() {
        let store = UserDictionarySettingsStore(defaults: defaults)
        XCTAssertTrue(store.addManual("缔约过失"))  // manual term — must survive the reset

        let record = HotwordLearningRecord(
            term: "Qwen3-ASR",
            source: .localRules,
            status: .pending,
            reason: "术语",
            learnedAt: Date(timeIntervalSince1970: 1))
        AutoLearnHotwordHistorySettings.save([record], defaults: defaults)
        XCTAssertTrue(store.confirmAuto(record))  // → auto dictionary term + .added ledger entry

        // Sanity: there really is auto state to clear.
        XCTAssertEqual(ContextHotwordSettings.autoHotwords(defaults: defaults), ["Qwen3-ASR"])
        XCTAssertNotNil(ContextHotwordSettings.autoMetadata(defaults: defaults)["Qwen3-ASR"])
        XCTAssertFalse(store.recentLearningRecords.isEmpty)

        store.resetAutoLearning()

        XCTAssertEqual(ContextHotwordSettings.autoHotwords(defaults: defaults), [])
        XCTAssertNil(ContextHotwordSettings.autoMetadata(defaults: defaults)["Qwen3-ASR"])
        XCTAssertTrue(store.recentLearningRecords.isEmpty)
        XCTAssertEqual(ContextHotwordSettings.hotwords(defaults: defaults), ["缔约过失"])  // manual intact
    }

    func testRemoveSeededDefaultsStripsLegacyBuiltinsOnceKeepingUserTerms() {
        // Simulate a pre-2026-06-29 install: the built-in example seeds had been folded into the
        // manual dictionary alongside a real user term.
        ContextHotwordSettings.addManual("Westlaw", defaults: defaults)  // legacy seed
        ContextHotwordSettings.addManual("Swift", defaults: defaults)    // legacy seed
        ContextHotwordSettings.addManual("缔约过失", defaults: defaults)  // genuine user term

        ContextHotwordSettings.removeSeededDefaultsIfNeeded(defaults: defaults)

        let after = ContextHotwordSettings.hotwords(defaults: defaults)
        XCTAssertFalse(after.contains("Westlaw"))  // legacy seed stripped
        XCTAssertFalse(after.contains("Swift"))     // legacy seed stripped
        XCTAssertTrue(after.contains("缔约过失"))    // user term untouched

        // Runs once: a user who later re-adds a former seed keeps it across a subsequent launch.
        ContextHotwordSettings.addManual("Westlaw", defaults: defaults)
        ContextHotwordSettings.removeSeededDefaultsIfNeeded(defaults: defaults)
        XCTAssertTrue(ContextHotwordSettings.hotwords(defaults: defaults).contains("Westlaw"))
    }

    func testRemoveSeededDefaultsNoOpsOnAFreshInstall() {
        // Fresh user: nothing seeded, nothing to strip — and it must not re-run.
        ContextHotwordSettings.addManual("法墨", defaults: defaults)
        ContextHotwordSettings.removeSeededDefaultsIfNeeded(defaults: defaults)
        XCTAssertEqual(ContextHotwordSettings.hotwords(defaults: defaults), ["法墨"])
    }

    func testFreshDownloadHasNoDefaultHotwords() {
        // Product guarantee: a brand-new download starts with an EMPTY dictionary. We never add
        // default hotwords — neither to the dictionary the user sees nor to the ASR biasing set —
        // even after the launch migration runs.
        ContextHotwordSettings.removeSeededDefaultsIfNeeded(defaults: defaults)
        XCTAssertEqual(ContextHotwordSettings.hotwords(defaults: defaults), [])
        XCTAssertTrue(ContextHotwordSettings.store(defaults: defaults).userTermEntries.isEmpty)
        XCTAssertTrue(
            ContextHotwordSettings.biasingSets(defaults: defaults, currentScene: nil).weakPrompt.isEmpty)
    }

    func testModeSelectionAndConfirmationPolicyUseStore() {
        let store = UserDictionarySettingsStore(defaults: defaults)

        XCTAssertFalse(store.autoLearnEnabled)
        store.setAutoLearnEnabled(true)
        XCTAssertTrue(store.autoLearnEnabled)

        XCTAssertEqual(store.currentMode, .localRules)
        store.selectMode(.localModel)
        XCTAssertEqual(store.currentMode, .localModel)

        store.setConfirmationPolicy(.confirmEveryTime)
        XCTAssertEqual(store.confirmationPolicy, .confirmEveryTime)
    }
}
