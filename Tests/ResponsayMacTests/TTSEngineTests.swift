import XCTest
@testable import ResponsayMac
import ResponsayCore

/// 193 — TTS engine selection + factory. Test standard T1.
final class TTSEngineTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: TTSEngine.defaultsKey)
        UserDefaults.standard.removeObject(forKey: "byok.tts.provider")
        super.tearDown()
    }

    func testDefaultsToLocalKokoroWhenUnsetAndNoCloudProvider() {
        UserDefaults.standard.removeObject(forKey: TTSEngine.defaultsKey)
        UserDefaults.standard.removeObject(forKey: "byok.tts.provider")
        XCTAssertEqual(TTSEngine.selected, .sherpaKokoroLocal)
    }

    /// 用户配了朗读云端语音(byok.tts.provider)但没手动选引擎 → 默认走该云端引擎,不再退回离线 Kokoro。
    func testDefaultsToConfiguredCloudProviderWhenEnginePickUnset() {
        let defaults = freshDefaults("cloud-default")
        defaults.set("gemini", forKey: "byok.tts.provider")
        XCTAssertEqual(TTSEngine.selected(defaults: defaults), .cloudGemini)
    }

    /// 手动选过引擎就以它为准,即便 byok.tts.provider 指向别的云端 provider。
    func testExplicitEnginePickWinsOverConfiguredCloudProvider() {
        let defaults = freshDefaults("explicit-wins")
        defaults.set("gemini", forKey: "byok.tts.provider")
        defaults.set(TTSEngine.sherpaKokoroLocal.rawValue, forKey: TTSEngine.defaultsKey)
        XCTAssertEqual(TTSEngine.selected(defaults: defaults), .sherpaKokoroLocal)
    }

    /// byok.tts.provider 指向没有云端 TTS 引擎的 provider(或空)时仍回落 Kokoro。
    func testUnknownOrEmptyCloudProviderFallsBackToKokoro() {
        let defaults = freshDefaults("no-match")
        defaults.set("deepseek", forKey: "byok.tts.provider")  // deepseek 无 TTS 引擎
        XCTAssertEqual(TTSEngine.selected(defaults: defaults), .sherpaKokoroLocal)
    }

    func testSelectedRoundTripsStoredRawValue() {
        UserDefaults.standard.set(TTSEngine.cloudMiniMax.rawValue, forKey: TTSEngine.defaultsKey)
        XCTAssertEqual(TTSEngine.selected, .cloudMiniMax)
    }

    func testUnknownRawValueFallsBackToDefault() {
        UserDefaults.standard.set("not-a-real-engine", forKey: TTSEngine.defaultsKey)
        XCTAssertEqual(TTSEngine.selected, .sherpaKokoroLocal)
    }

    func testLocalEngineIdMatchesRegistrySpec() {
        // 203's spec id and 193's enum rawValue must agree (the picker selects the model).
        XCTAssertEqual(TTSEngine.sherpaKokoroLocal.rawValue, LocalModelRegistry.defaultTTS.id)
        XCTAssertTrue(TTSEngine.sherpaKokoroLocal.isLocal)
        XCTAssertFalse(TTSEngine.cloudQwen.isLocal)
    }

    func testMiniMaxIsWiredToCatalog() {
        XCTAssertEqual(TTSEngine.cloudMiniMax.catalog?.providerID, "minimax")
        XCTAssertEqual(TTSEngine.cloudMiniMax.catalog?.defaults.modelID, "speech-2.8-hd")
        XCTAssertEqual(TTSEngine.cloudMiniMax.selectedVoiceID(defaults: freshDefaults("minimax")), "male-qn-qingse")
    }

    func testWiredCloudEnginesMapToCredentialSlots() {
        XCTAssertEqual(TTSEngine.cloudOpenAI.credentialSlot?.account, ProviderCredentialStore.Slot.openai.account)
        XCTAssertEqual(TTSEngine.cloudQwen.credentialSlot?.account, ProviderCredentialStore.Slot.dashscope.account)
        XCTAssertEqual(TTSEngine.cloudMimo.credentialSlot?.account, ProviderCredentialStore.Slot.mimo.account)
        XCTAssertEqual(TTSEngine.cloudMiniMax.credentialSlot?.account, ProviderCredentialStore.Slot.minimax.account)
        XCTAssertEqual(TTSEngine.cloudGemini.credentialSlot?.account, ProviderCredentialStore.Slot.gemini.account)
        XCTAssertNil(TTSEngine.sherpaKokoroLocal.credentialSlot)
    }

    func testGeminiIsWiredToCatalog() {
        XCTAssertEqual(TTSEngine.cloudGemini.providerID, "gemini")
        XCTAssertEqual(TTSEngine.cloudGemini.catalog?.providerID, "gemini")
        XCTAssertEqual(TTSEngine.cloudGemini.catalog?.defaults.modelID, "gemini-3.1-flash-tts-preview")
        // Single model — no 2.5 pro/flash.
        XCTAssertEqual(TTSEngine.cloudGemini.catalog?.models.map(\.id), ["gemini-3.1-flash-tts-preview"])
        XCTAssertEqual(TTSEngine.cloudGemini.selectedVoiceID(defaults: freshDefaults("gemini")), "Kore")
    }

    func testRetiredDoubaoSelectionFallsBackToQwenTTS() {
        UserDefaults.standard.set("cloud-doubao", forKey: TTSEngine.defaultsKey)
        XCTAssertEqual(TTSEngine.selected, .cloudQwen)
    }

    func testAllCasesHaveTitles() {
        for engine in TTSEngine.allCases {
            XCTAssertFalse(engine.title.isEmpty)
        }
    }

    // MARK: - 196 cloud engine ↔ catalog / voice mapping

    func testCloudEnginesMapToCatalogAndDefaultVoice() {
        let defaults = freshDefaults("catalog-default")
        XCTAssertEqual(TTSEngine.cloudOpenAI.providerID, "openai")
        XCTAssertEqual(TTSEngine.cloudOpenAI.catalog?.providerID, "openai")
        XCTAssertEqual(TTSEngine.cloudOpenAI.selectedVoiceID(defaults: defaults), "alloy")  // catalog default
        XCTAssertEqual(TTSEngine.cloudQwen.providerID, "qwen")
        XCTAssertNil(TTSEngine.sherpaKokoroLocal.providerID)
        XCTAssertNil(TTSEngine.sherpaKokoroLocal.selectedVoiceID(defaults: defaults))
    }

    func testSelectedVoiceHonorsValidStoredPickElseDefault() {
        let defaults = freshDefaults("voice-pick")
        let key = TTSEngine.cloudOpenAI.voiceDefaultsKey
        defaults.set("nova", forKey: key)
        XCTAssertEqual(TTSEngine.cloudOpenAI.selectedVoiceID(defaults: defaults), "nova")
        defaults.set("not-a-voice", forKey: key)
        XCTAssertEqual(TTSEngine.cloudOpenAI.selectedVoiceID(defaults: defaults), "alloy")  // invalid → default
    }

    private func freshDefaults(_ suffix: String) -> UserDefaults {
        let name = "TTSEngineTests.\(suffix)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
