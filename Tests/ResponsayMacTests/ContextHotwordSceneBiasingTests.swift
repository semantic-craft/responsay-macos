import XCTest
import ResponsayCore
@testable import ResponsayMac

/// P0a — scene-aware biasing: an auto-learned term injects only when the current app's register
/// tier matches where it was learned (or either side is unclassifiable). Manual terms stay global.
final class ContextHotwordSceneBiasingTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "test.contextHotword.sceneBiasing"

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

    // MARK: - Pure rule

    func testSceneSuppressesOnlyWhenBothKnownAndDifferent() {
        XCTAssertTrue(ContextHotwordSettings.sceneSuppresses(stored: .legal, current: .chat))
        XCTAssertFalse(ContextHotwordSettings.sceneSuppresses(stored: .legal, current: .legal))
        XCTAssertFalse(ContextHotwordSettings.sceneSuppresses(stored: nil, current: .chat))   // global term
        XCTAssertFalse(ContextHotwordSettings.sceneSuppresses(stored: .legal, current: nil))  // unknown app
    }

    // MARK: - End-to-end through biasingSets

    func testChatTermSuppressedInDocumentButNotInChatOrUnknownScene() {
        // Learned while dictating in WeChat (bundleID contains "wechat" → .chat). bundleID-based
        // tiers (chat/mail/document) are what auto-learn sees, since it fires where you dictate —
        // native apps, not while browsing. (Browser-domain tiers like legal *sites* need the active
        // tab URL at learn + ASR time, which is a follow-up; native legal apps use legalSeeds.)
        XCTAssertTrue(ContextHotwordSettings.addAuto(
            "在吗", appName: "com.tencent.xinWeChat", defaults: defaults))

        XCTAssertFalse(
            ContextHotwordSettings.biasingSets(defaults: defaults, currentScene: .document)
                .hardMatchUser.contains("在吗"),
            "a chat-learned term should not bias document dictation")
        XCTAssertTrue(
            ContextHotwordSettings.biasingSets(defaults: defaults, currentScene: .chat)
                .hardMatchUser.contains("在吗"),
            "same-tier scene keeps the term")
        XCTAssertTrue(
            ContextHotwordSettings.biasingSets(defaults: defaults, currentScene: nil)
                .hardMatchUser.contains("在吗"),
            "unknown current scene suppresses nothing (pre-P0a behavior)")
    }

    func testUnclassifiedLearnAppStaysGlobal() {
        // Learned in an app the register table doesn't know (→ scene nil → global).
        XCTAssertTrue(ContextHotwordSettings.addAuto(
            "LRU", appName: "com.unknown.editor", defaults: defaults))

        XCTAssertTrue(
            ContextHotwordSettings.biasingSets(defaults: defaults, currentScene: .chat)
                .hardMatchUser.contains("LRU"),
            "a globally-learned term injects everywhere")
    }

    func testManualTermNeverSuppressed() {
        XCTAssertTrue(ContextHotwordSettings.addManual("WestLaw", defaults: defaults))

        XCTAssertTrue(
            ContextHotwordSettings.biasingSets(defaults: defaults, currentScene: .chat)
                .hardMatchUser.contains("WestLaw"),
            "manual terms are always global regardless of scene")
    }
}
