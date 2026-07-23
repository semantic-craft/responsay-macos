import XCTest
import ResponsayCore
@testable import ResponsayMac

@MainActor
final class AutoLearnHotwordNotificationPresenterTests: XCTestCase {
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

    func testUndoNotificationRemovesAutoTermAndTombstonesIt() {
        let proposal = HotwordCandidateProposal(
            term: "Claude Code",
            source: .localRules,
            confidence: 0.9,
            reason: "用户纠正")
        XCTAssertTrue(ContextHotwordSettings.addAuto("Claude Code", source: .localRules, reason: "用户纠正"))
        AutoLearnHotwordHistorySettings.append(proposal, status: .added)

        AutoLearnHotwordNotificationPresenter.shared.undoAutoLearnedTerm("Claude Code")

        XCTAssertFalse(ContextHotwordSettings.autoHotwords().contains("Claude Code"))
        let history = HotwordLearningHistory(records: AutoLearnHotwordHistorySettings.records())
        XCTAssertTrue(history.tombstonedTerms().contains("Claude Code"))
    }

    nonisolated private static let defaultsKeys = [
        ContextHotwordSettings.autoDefaultsKey,
        ContextHotwordSettings.autoMetadataDefaultsKey,
        AutoLearnHotwordHistorySettings.historyKey
    ]
}
