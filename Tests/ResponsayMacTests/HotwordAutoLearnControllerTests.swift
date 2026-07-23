import XCTest
import ResponsayCore
@testable import ResponsayMac

@MainActor
final class HotwordAutoLearnControllerTests: XCTestCase {
    nonisolated(unsafe) private var savedDefaults: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        savedDefaults = [:]
        for key in Self.defaultsKeys {
            if let value = UserDefaults.standard.object(forKey: key) {
                savedDefaults[key] = value
            }
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        for key in Self.defaultsKeys {
            if let value = savedDefaults[key] {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        super.tearDown()
    }

    func testCheckForCorrectionAddsAutoHotword() async {
        UserDefaults.standard.set(true, forKey: AutoLearnHotwordSettings.key)
        var snapshot = (text: "我在用 cloud code 写代码", app: "Notes", sceneID: "note-1", windowTitle: "Test")
        var addedTerms: [String] = []
        let processor = AutoLearnHotwordProcessor(
            isEnabled: { true },
            mode: { .localRules },
            confirmationPolicy: { .autoAddHighConfidence },
            existingManualTerms: { [] },
            existingAutoTerms: { [] },
            addAuto: { proposal in addedTerms.append(proposal.term); return true },
            record: { _, _ in true })
        let controller = HotwordAutoLearnController(
            snapshotReader: { snapshot },
            processor: processor)

        controller.noteInsertion()
        snapshot.text = "我在用 Claude Code 写代码"

        XCTAssertTrue(checkAfterStablePolls(controller))
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(addedTerms, ["Claude Code"])
    }

    func testCorrectionPersistsClaudeCodeIntoActiveDictionary() async {
        UserDefaults.standard.set(true, forKey: AutoLearnHotwordSettings.key)
        var snapshot = (text: "我在用 cloud code 写代码", app: "Notes", sceneID: "note-1", windowTitle: "Test")
        let processor = AutoLearnHotwordProcessor(
            isEnabled: { AutoLearnHotwordSettings.isEnabled },
            mode: { .localRules },
            confirmationPolicy: { .autoAddHighConfidence },
            existingManualTerms: { Set(ContextHotwordSettings.hotwords()) },
            existingAutoTerms: { Set(ContextHotwordSettings.autoHotwords()) },
            addAuto: { proposal in
                ContextHotwordSettings.addAuto(
                    proposal.term,
                    source: proposal.source,
                    reason: proposal.reason)
            },
            record: { proposal, status in
                AutoLearnHotwordHistorySettings.append(proposal, status: status)
            })
        let controller = HotwordAutoLearnController(
            snapshotReader: { snapshot },
            processor: processor)

        controller.noteInsertion()
        snapshot.text = "我在用 Claude Code 写代码"
        XCTAssertTrue(checkAfterStablePolls(controller))
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(ContextHotwordSettings.autoHotwords().contains("Claude Code"))
        XCTAssertTrue(ContextHotwordSettings.biasingSets().weakPrompt.contains("Claude Code"))
        XCTAssertEqual(AutoLearnHotwordHistorySettings.records().first?.term, "Claude Code")
        XCTAssertEqual(AutoLearnHotwordHistorySettings.records().first?.sourceTerm, "cloud code")
    }

    func testPartialManualEditWaitsForStableFinalText() async {
        UserDefaults.standard.set(true, forKey: AutoLearnHotwordSettings.key)
        var snapshot = (text: "我最近在用 Cloud Xcode 写代码。", app: "TextEdit", sceneID: "textedit", windowTitle: "Untitled")
        var addedTerms: [String] = []
        let processor = AutoLearnHotwordProcessor(
            isEnabled: { true },
            mode: { .localRules },
            confirmationPolicy: { .autoAddHighConfidence },
            existingManualTerms: { [] },
            existingAutoTerms: { [] },
            addAuto: { proposal in addedTerms.append(proposal.term); return true },
            record: { _, _ in true })
        let controller = HotwordAutoLearnController(
            snapshotReader: { snapshot },
            processor: processor)

        controller.noteInsertion()
        snapshot.text = "我最近在用 Clou Xcode 写代码。"
        XCTAssertFalse(controller.checkForCorrection())
        snapshot.text = "我最近在用 Claude Code 写代码。"

        XCTAssertTrue(checkAfterStablePolls(controller))
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(addedTerms, ["Claude Code"])
    }

    func testDisabledAutoLearnDoesNotWatchOrAdd() {
        UserDefaults.standard.set(false, forKey: AutoLearnHotwordSettings.key)
        var snapshot = (text: "我在用 cloud code 写代码", app: "Notes", sceneID: "note-1", windowTitle: "Test")
        var addedTerms: [String] = []
        let processor = AutoLearnHotwordProcessor(
            isEnabled: { true },
            mode: { .localRules },
            confirmationPolicy: { .autoAddHighConfidence },
            existingManualTerms: { [] },
            existingAutoTerms: { [] },
            addAuto: { proposal in addedTerms.append(proposal.term); return true },
            record: { _, _ in true })
        let controller = HotwordAutoLearnController(
            snapshotReader: { snapshot },
            processor: processor)

        controller.noteInsertion()
        snapshot.text = "我在用 Claude Code 写代码"

        XCTAssertFalse(controller.checkForCorrection())
        XCTAssertTrue(addedTerms.isEmpty)
    }

    nonisolated private static let defaultsKeys = [
        AutoLearnHotwordSettings.key,
        ContextHotwordSettings.defaultsKey,
        ContextHotwordSettings.autoDefaultsKey,
        ContextHotwordSettings.autoMetadataDefaultsKey,
        AutoLearnHotwordHistorySettings.historyKey
    ]

    private func checkAfterStablePolls(_ controller: HotwordAutoLearnController) -> Bool {
        for _ in 0..<6 {
            XCTAssertFalse(controller.checkForCorrection())
        }
        return controller.checkForCorrection()
    }
}
