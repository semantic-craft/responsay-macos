import XCTest
@testable import ResponsayMac

/// 朗读卡片补写 `byok.tts.provider`：配好云端 TTS 却仍默认离线 Kokoro 的回归测试。
/// 卡片只写 `byok.tts.<id>.*` + 钥匙串，从不写 active provider，而 `TTSEngine.selected`
/// 的云端优先分支正是读它 —— 于是那段逻辑永远走不到。
final class TTSActiveProviderTests: XCTestCase {

    /// 主回归：设置页配好阿里云 TTS(有 scoped 配置)但没手选过引擎 → 认领为 active provider,
    /// `TTSEngine.selected` 因此给出云端引擎而不是 Kokoro。
    func testBackfillAdoptsConfiguredProviderSoCloudWinsOverKokoro() {
        let defaults = freshDefaults("adopt-configured")
        defaults.set("qwen-audio-3.0-tts-flash", forKey: "byok.tts.qwen.model")

        TTSActiveProvider.adoptShownProviderIfUnset("qwen", hasCredential: false, defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: "byok.tts.provider"), "qwen")
        XCTAssertEqual(TTSEngine.selected(defaults: defaults), .cloudQwen)
    }

    /// 只填了密钥、没动过任何字段(无 scoped model)也算已配置 —— 用卡片已加载到内存的凭据判断,
    /// 不额外读钥匙串(217 冻结路径)。
    func testBackfillAdoptsWhenOnlyCredentialIsPresent() {
        let defaults = freshDefaults("adopt-credential-only")

        TTSActiveProvider.adoptShownProviderIfUnset("qwen", hasCredential: true, defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: "byok.tts.provider"), "qwen")
    }

    /// 不变量:完全没配过云端 TTS 的机器必须留空 provider,默认继续是本机 Kokoro。
    func testBackfillLeavesUnconfiguredInstallOnKokoro() {
        let defaults = freshDefaults("unconfigured")

        TTSActiveProvider.adoptShownProviderIfUnset("qwen", hasCredential: false, defaults: defaults)

        XCTAssertNil(defaults.string(forKey: "byok.tts.provider"))
        XCTAssertEqual(TTSEngine.selected(defaults: defaults), .sherpaKokoroLocal)
    }

    /// 已有 active provider 时补写不得改动它(补写只针对老装机的空值)。
    func testBackfillDoesNotOverrideExistingSelection()  {
        let defaults = freshDefaults("existing-selection")
        defaults.set("mimo", forKey: "byok.tts.provider")
        defaults.set("qwen-audio-3.0-tts-flash", forKey: "byok.tts.qwen.model")

        TTSActiveProvider.adoptShownProviderIfUnset("qwen", hasCredential: true, defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: "byok.tts.provider"), "mimo")
    }

    /// 用户在卡片上主动切服务商是明确意图:即便该服务商还没配过也照写。
    func testExplicitAdoptWritesEvenWhenProviderHasNoConfigYet() {
        let defaults = freshDefaults("explicit-switch")
        defaults.set("qwen", forKey: "byok.tts.provider")

        TTSActiveProvider.adopt("gemini", defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: "byok.tts.provider"), "gemini")
        XCTAssertEqual(TTSEngine.selected(defaults: defaults), .cloudGemini)
    }

    /// 认领 ≠ 重置:只写 provider 一个键,用户在卡片里选的音色/模型/端点原样保留
    /// (对照 `CapabilitySelectionSync.selectProvider`,那条路会用 preset 默认值覆写这些字段)。
    func testAdoptDoesNotResetTheUsersStoredConfig() {
        let defaults = freshDefaults("adopt-preserves-config")
        defaults.set("qwen-audio-3.0-tts-flash", forKey: "byok.tts.qwen.model")
        defaults.set("loongeva_v3.6", forKey: "byok.tts.qwen.voice")
        defaults.set("wss://dashscope.aliyuncs.com/api-ws/v1/inference", forKey: "byok.tts.qwen.baseURL")

        TTSActiveProvider.adoptShownProviderIfUnset("qwen", hasCredential: true, defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: "byok.tts.qwen.model"), "qwen-audio-3.0-tts-flash")
        XCTAssertEqual(defaults.string(forKey: "byok.tts.qwen.voice"), "loongeva_v3.6")
        XCTAssertEqual(defaults.string(forKey: "byok.tts.qwen.baseURL"), "wss://dashscope.aliyuncs.com/api-ws/v1/inference")
    }

    /// 显式选过引擎仍然优先于补写出来的 provider(`TTSEngine.selected` 的先后顺序不变)。
    func testExplicitEnginePickStillWinsAfterBackfill() {
        let defaults = freshDefaults("explicit-engine-wins")
        defaults.set("qwen-audio-3.0-tts-flash", forKey: "byok.tts.qwen.model")
        defaults.set(TTSEngine.sherpaKokoroLocal.rawValue, forKey: TTSEngine.defaultsKey)

        TTSActiveProvider.adoptShownProviderIfUnset("qwen", hasCredential: true, defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: "byok.tts.provider"), "qwen")
        XCTAssertEqual(TTSEngine.selected(defaults: defaults), .sherpaKokoroLocal)
    }

    private func freshDefaults(_ suffix: String) -> UserDefaults {
        let name = "TTSActiveProviderTests.\(suffix)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
