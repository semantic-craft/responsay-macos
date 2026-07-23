import XCTest
import ResponsayCore
@testable import ResponsayMac

final class AutoLearnHotwordStorageTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "test.autoLearnHotwordStorage"

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

    func testAutoTermStoresLearningMetadata() {
        let added = ContextHotwordSettings.addAuto(
            "Responsay",
            source: .localModel,
            reason: "本地模型识别为品牌词",
            learnedAt: Date(timeIntervalSince1970: 10),
            defaults: defaults)

        let entry = ContextHotwordSettings.store(defaults: defaults).userTermEntries.first

        XCTAssertTrue(added)
        XCTAssertEqual(entry?.text, "Responsay")
        XCTAssertEqual(entry?.source, .auto)
        XCTAssertEqual(entry?.learnedSource, .localModel)
        XCTAssertEqual(entry?.learnedAt, Date(timeIntervalSince1970: 10))
    }

    func testManualTermPreventsAutoOverride() {
        ContextHotwordSettings.addManual("Responsay", defaults: defaults)

        let added = ContextHotwordSettings.addAuto(
            "Responsay",
            source: .cloudBYOK,
            reason: "云端候选",
            defaults: defaults)

        XCTAssertFalse(added)
        XCTAssertEqual(ContextHotwordSettings.autoHotwords(defaults: defaults), [])
    }

    func testRemovingManualTermWritesBackToSettingsStore() {
        ContextHotwordSettings.addManual("Responsay", defaults: defaults)
        ContextHotwordSettings.addManual("CLSCI", defaults: defaults)

        ContextHotwordSettings.removeManual("Responsay", defaults: defaults)

        XCTAssertEqual(ContextHotwordSettings.hotwords(defaults: defaults), ["CLSCI"])
        XCTAssertEqual(
            ContextHotwordSettings.store(defaults: defaults).userTermEntries.map(\.text),
            ["CLSCI"])
    }

    func testRenamingManualTermWritesBackToSettingsStore() {
        ContextHotwordSettings.addManual("Responsay", defaults: defaults)
        ContextHotwordSettings.addManual("CLSCI", defaults: defaults)

        let renamed = ContextHotwordSettings.renameManual("Responsay", to: "Responsay App", defaults: defaults)

        XCTAssertTrue(renamed)
        XCTAssertEqual(ContextHotwordSettings.hotwords(defaults: defaults), ["CLSCI", "Responsay App"])
        XCTAssertEqual(
            ContextHotwordSettings.store(defaults: defaults).userTermEntries.map(\.text),
            ["CLSCI", "Responsay App"])
    }

    func testManualEditsFeedActiveHotwordProtection() {
        ContextHotwordSettings.addManual("Qwen3-ASR", defaults: defaults)

        let protectedBeforeEdit = HotwordHardMatch.enforce(
            "I used qwen3asr today",
            hotwords: ContextHotwordSettings.biasingSets(defaults: defaults).weakPrompt)

        XCTAssertEqual(protectedBeforeEdit.text, "I used Qwen3-ASR today")

        let renamed = ContextHotwordSettings.renameManual("Qwen3-ASR", to: "Claude-Desktop", defaults: defaults)
        let oldTermAfterEdit = HotwordHardMatch.enforce(
            "I used qwen3asr today",
            hotwords: ContextHotwordSettings.biasingSets(defaults: defaults).weakPrompt)
        let newTermAfterEdit = HotwordHardMatch.enforce(
            "I used claude desktop today",
            hotwords: ContextHotwordSettings.biasingSets(defaults: defaults).weakPrompt)

        XCTAssertTrue(renamed)
        XCTAssertEqual(oldTermAfterEdit.text, "I used qwen3asr today")
        XCTAssertEqual(newTermAfterEdit.text, "I used Claude-Desktop today")
    }

    func testLearnedCorrectionAliasFeedsActiveHotwordProtection() {
        ContextHotwordSettings.addAuto(
            "Zotero",
            source: .localRules,
            reason: "用户纠正",
            defaults: defaults)
        AutoLearnHotwordHistorySettings.append(
            HotwordCandidateProposal(
                term: "Zotero",
                source: .localRules,
                confidence: 0.92,
                reason: "用户纠正",
                sourceTerm: "Zeta 龙"),
            status: .added,
            defaults: defaults)

        let result = ContextHotwordSettings.biasingSets(defaults: defaults).enforce("open Zeta 龙")

        XCTAssertEqual(result.text, "open Zotero")
    }

    func testRenamingAutoTermPreservesLearningMetadata() {
        ContextHotwordSettings.addAuto(
            "Responsay",
            source: .localModel,
            reason: "本地模型识别为品牌词",
            learnedAt: Date(timeIntervalSince1970: 10),
            defaults: defaults)

        let renamed = ContextHotwordSettings.renameAuto("Responsay", to: "Responsay App", defaults: defaults)

        let entry = ContextHotwordSettings.store(defaults: defaults).userTermEntries.first
        XCTAssertTrue(renamed)
        XCTAssertEqual(ContextHotwordSettings.autoHotwords(defaults: defaults), ["Responsay App"])
        XCTAssertEqual(entry?.text, "Responsay App")
        XCTAssertEqual(entry?.source, .auto)
        XCTAssertEqual(entry?.learnedSource, .localModel)
        XCTAssertEqual(entry?.learnedAt, Date(timeIntervalSince1970: 10))
        XCTAssertNil(ContextHotwordSettings.autoMetadata(defaults: defaults)["Responsay"])
    }

    func testRenamingToDuplicateTermIsRejected() {
        ContextHotwordSettings.addManual("Responsay", defaults: defaults)
        ContextHotwordSettings.addManual("CLSCI", defaults: defaults)

        let renamed = ContextHotwordSettings.renameManual("Responsay", to: "CLSCI", defaults: defaults)

        XCTAssertFalse(renamed)
        XCTAssertEqual(ContextHotwordSettings.hotwords(defaults: defaults), ["CLSCI", "Responsay"])
    }

    func testRemovingAutoTermAlsoRemovesMetadata() {
        ContextHotwordSettings.addAuto(
            "Responsay",
            source: .localRules,
            reason: "用户纠正",
            defaults: defaults)

        ContextHotwordSettings.removeAuto("Responsay", defaults: defaults)

        XCTAssertEqual(ContextHotwordSettings.autoHotwords(defaults: defaults), [])
        XCTAssertNil(ContextHotwordSettings.autoMetadata(defaults: defaults)["Responsay"])
    }
}
