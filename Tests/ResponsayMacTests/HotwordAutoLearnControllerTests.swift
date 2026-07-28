import XCTest
import ResponsayCore
@testable import ResponsayMac

@MainActor
final class HotwordAutoLearnControllerTests: XCTestCase {
    // These tests drive the real learning path (dictionary writes + the toast post), and the
    // suite runs inside the app itself (`TEST_HOST`). Both sinks are therefore isolated: an
    // own defaults suite, and an injected `notify`. Touching `UserDefaults.standard` here used
    // to write the machine's live 识别词典 and fire a real toast at whoever was at the keyboard,
    // and a run interrupted between setUp and tearDown left that dictionary emptied.
    private var defaults: UserDefaults!
    private let suite = "test.hotwordAutoLearnController"

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

    func testCheckForCorrectionAddsAutoHotword() async {
        defaults.set(true, forKey: AutoLearnHotwordSettings.key)
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
            processor: processor,
            isEnabled: { [defaults] in AutoLearnHotwordSettings.resolve(defaults: defaults!) },
            notify: { _ in })

        controller.noteInsertion()
        snapshot.text = "我在用 Claude Code 写代码"

        XCTAssertTrue(checkAfterStablePolls(controller))
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(addedTerms, ["Claude Code"])
    }

    func testCorrectionPersistsClaudeCodeIntoActiveDictionary() async {
        defaults.set(true, forKey: AutoLearnHotwordSettings.key)
        var snapshot = (text: "我在用 cloud code 写代码", app: "Notes", sceneID: "note-1", windowTitle: "Test")
        let processor = AutoLearnHotwordProcessor(
            isEnabled: { AutoLearnHotwordSettings.isEnabled },
            mode: { .localRules },
            confirmationPolicy: { .autoAddHighConfidence },
            existingManualTerms: { [defaults] in Set(ContextHotwordSettings.hotwords(defaults: defaults!)) },
            existingAutoTerms: { [defaults] in Set(ContextHotwordSettings.autoHotwords(defaults: defaults!)) },
            addAuto: { [defaults] proposal in
                ContextHotwordSettings.addAuto(
                    proposal.term,
                    source: proposal.source,
                    reason: proposal.reason,
                    defaults: defaults!)
            },
            record: { [defaults] proposal, status in
                AutoLearnHotwordHistorySettings.append(proposal, status: status, defaults: defaults!)
            })
        let controller = HotwordAutoLearnController(
            snapshotReader: { snapshot },
            processor: processor,
            isEnabled: { [defaults] in AutoLearnHotwordSettings.resolve(defaults: defaults!) },
            notify: { _ in })

        controller.noteInsertion()
        snapshot.text = "我在用 Claude Code 写代码"
        XCTAssertTrue(checkAfterStablePolls(controller))
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(ContextHotwordSettings.autoHotwords(defaults: defaults).contains("Claude Code"))
        XCTAssertTrue(ContextHotwordSettings.biasingSets(defaults: defaults).weakPrompt.contains("Claude Code"))
        XCTAssertEqual(AutoLearnHotwordHistorySettings.records(defaults: defaults).first?.term, "Claude Code")
        XCTAssertEqual(AutoLearnHotwordHistorySettings.records(defaults: defaults).first?.sourceTerm, "cloud code")
    }

    func testPartialManualEditWaitsForStableFinalText() async {
        defaults.set(true, forKey: AutoLearnHotwordSettings.key)
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
            processor: processor,
            isEnabled: { [defaults] in AutoLearnHotwordSettings.resolve(defaults: defaults!) },
            notify: { _ in })

        controller.noteInsertion()
        snapshot.text = "我最近在用 Clou Xcode 写代码。"
        XCTAssertFalse(controller.checkForCorrection())
        snapshot.text = "我最近在用 Claude Code 写代码。"

        XCTAssertTrue(checkAfterStablePolls(controller))
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(addedTerms, ["Claude Code"])
    }

    func testDisabledAutoLearnDoesNotWatchOrAdd() {
        defaults.set(false, forKey: AutoLearnHotwordSettings.key)
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
            processor: processor,
            isEnabled: { [defaults] in AutoLearnHotwordSettings.resolve(defaults: defaults!) },
            notify: { _ in })

        controller.noteInsertion()
        snapshot.text = "我在用 Claude Code 写代码"

        XCTAssertFalse(controller.checkForCorrection())
        XCTAssertTrue(addedTerms.isEmpty)
    }

    private func checkAfterStablePolls(_ controller: HotwordAutoLearnController) -> Bool {
        for _ in 0..<6 {
            XCTAssertFalse(controller.checkForCorrection())
        }
        return controller.checkForCorrection()
    }
}
