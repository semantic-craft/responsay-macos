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

    func testGeminiIsWiredToCatalog() {
        XCTAssertEqual(TTSEngine.cloudGemini.providerID, "gemini")
        XCTAssertEqual(TTSEngine.cloudGemini.catalog?.providerID, "gemini")
        XCTAssertEqual(TTSEngine.cloudGemini.catalog?.defaults.modelID, "gemini-3.1-flash-tts-preview")
        // Single model — no 2.5 pro/flash.
        XCTAssertEqual(TTSEngine.cloudGemini.catalog?.models.map(\.id), ["gemini-3.1-flash-tts-preview"])
        XCTAssertEqual(TTSEngine.cloudGemini.selectedVoiceID(defaults: freshDefaults("gemini")), "Kore")
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

    /// 设置卡「音色」菜单里的每一项都必须在 TTS catalog 里 —— selectedVoiceID 拿 catalog.voices
    /// 校验用户选中的音色,菜单有而 catalog 没有的项会被静默换回默认音色,用户听到的不是他选的人声。
    /// (MiniMax 曾漏 male-qn-jingying / female-yujie / Sweet_Girl / Attractive_Girl 四项。)
    func testEveryPresetVoiceOfferedByTheCardResolves() {
        for preset in ProviderCatalog.all where !preset.presetVoices.isEmpty {
            guard let catalog = TTSProviderCatalogPresets.catalog(for: preset.id) else { continue }
            let known = Set(catalog.voices.map(\.id))
            for voice in preset.presetVoices {
                XCTAssertTrue(known.contains(voice.id),
                              "\(preset.id) 菜单提供的音色 \(voice.id) 不在 TTS catalog 里,选中后会被丢回默认音色")
            }
        }
    }

    func testSelectedVoiceHonorsProviderScopedPickElseDefault() {
        let defaults = freshDefaults("voice-pick")
        defaults.set("openai", forKey: "byok.tts.provider")
        defaults.set("nova", forKey: "byok.tts.openai.voice")
        XCTAssertEqual(TTSEngine.cloudOpenAI.selectedVoiceID(defaults: defaults), "nova")
        defaults.set("not-a-voice", forKey: "byok.tts.openai.voice")
        XCTAssertEqual(TTSEngine.cloudOpenAI.selectedVoiceID(defaults: defaults), "not-a-voice")
    }

    func testLegacyVoiceSlotCannotOverrideTheSharedProviderSelection() {
        let defaults = freshDefaults("legacy-voice-ignored")
        defaults.set("qwen", forKey: "byok.tts.provider")
        defaults.set("unsupported-qwen-voice", forKey: "byok.tts.voice")
        defaults.set("unsupported-qwen-voice", forKey: "byok.tts.qwen.voice")
        defaults.set("longjielidou_v3.6", forKey: "ttsVoice.cloud-qwen-tts")

        XCTAssertEqual(TTSEngine.cloudQwen.selectedVoiceID(defaults: defaults), "loongeva_v3.6")
    }

    func testReaderVoicePickWritesTheSameScopedSettingAsTheConfigCard() {
        let defaults = freshDefaults("voice-shared-setting")
        defaults.set("qwen", forKey: "byok.tts.provider")
        defaults.set("unsupported-qwen-voice", forKey: "byok.tts.voice")
        defaults.set("unsupported-qwen-voice", forKey: "byok.tts.qwen.voice")

        TTSEngine.cloudQwen.setSelectedVoiceID("longjielidou_v3.6", defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: "byok.tts.qwen.voice"), "longjielidou_v3.6")
        XCTAssertEqual(TTSEngine.cloudQwen.selectedVoiceID(defaults: defaults), "longjielidou_v3.6")
    }

    func testReaderVoicePickPublishesAConfigurationChange() {
        let defaults = freshDefaults("voice-change-notification")
        defaults.set("qwen", forKey: "byok.tts.provider")
        let changed = expectation(forNotification: .modelConfigurationDidChange, object: nil)

        TTSEngine.cloudQwen.setSelectedVoiceID("longanhuan_v3.6", defaults: defaults)

        wait(for: [changed], timeout: 0.2)
    }

    private func freshDefaults(_ suffix: String) -> UserDefaults {
        let name = "TTSEngineTests.\(suffix)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
