import XCTest
import ResponsayCore
@testable import ResponsayMac

final class TTSDefaultSelectionTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        super.setUp()
        suite = "TTSDefaultSelectionTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    private func activate(keys: [String: String] = [:]) {
        TTSDefaultSelection.activateConfiguredDefault(defaults: defaults, keyReader: { keys[$0] })
    }

    func testUnconfiguredInstallAndProfileWithoutCredentialStayLocal() {
        activate()
        XCTAssertEqual(TTSEngine.selected(defaults: defaults), .sherpaKokoroLocal)
        defaults.set("gemini", forKey: "byok.tts.provider")
        defaults.set("Kore", forKey: "byok.tts.gemini.voice")
        activate()
        XCTAssertEqual(TTSEngine.selected(defaults: defaults), .sherpaKokoroLocal)
    }

    func testExistingCloudConfigurationReplacesAbsentInvalidAndOldLocalDefaults() {
        for raw in [nil, "obsolete-engine", TTSEngine.sherpaKokoroLocal.rawValue] as [String?] {
            defaults.set(raw, forKey: TTSEngine.defaultsKey)
            defaults.set("gemini", forKey: "byok.tts.provider")
            activate(keys: ["byok.tts.gemini": "synthetic-tts-key"])
            XCTAssertEqual(TTSEngine.selected(defaults: defaults), .cloudGemini)
        }
    }

    func testExplicitLocalPickSurvivesConfigurationAndRelaunch() {
        ModelRouteSelectionActions.applyTTSSelection(TTSEngine.sherpaKokoroLocal.rawValue, defaults: defaults)
        activate(keys: ["byok.tts.qwen": "synthetic-tts-key"])
        XCTAssertEqual(TTSEngine.selected(defaults: defaults), .sherpaKokoroLocal)
        let reopened = UserDefaults(suiteName: suite)!
        TTSDefaultSelection.activateConfiguredDefault(defaults: reopened, keyReader: { _ in "synthetic-tts-key" })
        XCTAssertEqual(TTSEngine.selected(defaults: reopened), .sherpaKokoroLocal)
    }

    func testSavedCloudRouteStaysSelectedEvenIfItsCredentialIsUnavailable() {
        defaults.set(TTSEngine.cloudOpenAI.rawValue, forKey: TTSEngine.defaultsKey)
        activate(keys: ["byok.tts.qwen": "synthetic-tts-key"])
        XCTAssertEqual(TTSEngine.selected(defaults: defaults), .cloudOpenAI)
    }

    func testPreferredConfiguredProviderWinsThenRemainsStable() {
        defaults.set("gemini", forKey: "byok.tts.provider")
        let keys = ["byok.tts.gemini": "synthetic-gemini-key", "byok.tts.qwen": "synthetic-qwen-key"]
        activate(keys: keys)
        XCTAssertEqual(TTSEngine.selected(defaults: defaults), .cloudGemini)
        defaults.set("qwen", forKey: "byok.tts.provider")
        activate(keys: keys)
        XCTAssertEqual(TTSEngine.selected(defaults: defaults), .cloudGemini)
    }

    func testIncompletePreferredProviderDoesNotHideAnotherConfiguredVoice() {
        defaults.set("qwen", forKey: "byok.tts.provider")
        activate(keys: ["byok.tts.gemini": "synthetic-gemini-key"])
        XCTAssertEqual(TTSEngine.selected(defaults: defaults), .cloudGemini)
    }

    func testLLMKeyAndWhitespaceTTSKeyDoNotCountAsConfiguredTTS() {
        activate(keys: ["byok.qwen": "synthetic-llm-key", "byok.tts.gemini": " \n"])
        XCTAssertEqual(TTSEngine.selected(defaults: defaults), .sherpaKokoroLocal)
    }

    func testInvalidEndpointDoesNotAutomaticallySelectCloud() {
        defaults.set("not-a-url", forKey: "byok.tts.openai.baseURL")
        activate(keys: ["byok.tts.openai": "synthetic-openai-key"])
        XCTAssertEqual(TTSEngine.selected(defaults: defaults), .sherpaKokoroLocal)
    }

    func testAutomaticSelectionNotifiesMenuAndSettings() {
        let changed = expectation(forNotification: .modelConfigurationDidChange, object: nil)
        activate(keys: ["byok.tts.gemini": "synthetic-gemini-key"])
        wait(for: [changed], timeout: 0.2)
        XCTAssertEqual(ModelRouteCatalog.currentTTSId(defaults: defaults), TTSEngine.cloudGemini.rawValue)
    }
}
