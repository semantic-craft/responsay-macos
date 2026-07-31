import XCTest
@testable import ResponsayMac

/// Keeps the TTS route, active provider and provider-scoped runtime configuration synchronized,
/// including launch migration for installs that retained config but lost both route pointers.
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
        defaults.set("OldProviderVoice", forKey: "byok.tts.voice")

        TTSActiveProvider.adopt("gemini", defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: "byok.tts.provider"), "gemini")
        XCTAssertEqual(defaults.string(forKey: TTSEngine.defaultsKey), TTSEngine.cloudGemini.rawValue)
        XCTAssertEqual(TTSEngine.selected(defaults: defaults), .cloudGemini)
        XCTAssertNil(defaults.string(forKey: "byok.tts.gemini.voice"))
        XCTAssertNotEqual(defaults.string(forKey: "byok.tts.voice"), "OldProviderVoice")
    }

    /// Explicitly choosing a provider in the connection card is also a route choice. It must
    /// replace a stale/local engine pick and restore that provider's scoped configuration into
    /// the active keys consumed by the runtime engine.
    func testExplicitAdoptReplacesLocalEngineAndRestoresScopedConfig() {
        let defaults = freshDefaults("explicit-replaces-local")
        defaults.set(TTSEngine.sherpaKokoroLocal.rawValue, forKey: TTSEngine.defaultsKey)
        defaults.set("custom-mimo-tts", forKey: "byok.tts.mimo.model")
        defaults.set("Mia", forKey: "byok.tts.mimo.voice")
        defaults.set("https://api.xiaomimimo.com/v1", forKey: "byok.tts.mimo.baseURL")

        TTSActiveProvider.adopt("mimo", defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: TTSEngine.defaultsKey), TTSEngine.cloudMimo.rawValue)
        XCTAssertEqual(defaults.string(forKey: "byok.tts.provider"), "mimo")
        XCTAssertEqual(defaults.string(forKey: "byok.tts.model"), "custom-mimo-tts")
        XCTAssertEqual(defaults.string(forKey: "byok.tts.voice"), "Mia")
        XCTAssertEqual(defaults.string(forKey: "byok.tts.baseURL"), "https://api.xiaomimimo.com/v1")
    }

    /// Activating a provider mirrors its scoped values to the runtime keys without mutating or
    /// replacing the user's durable model / voice / endpoint configuration.
    func testAdoptDoesNotResetTheUsersStoredConfig() {
        let defaults = freshDefaults("adopt-preserves-config")
        defaults.set("qwen-audio-3.0-tts-flash", forKey: "byok.tts.qwen.model")
        defaults.set("loongeva_v3.6", forKey: "byok.tts.qwen.voice")
        defaults.set("wss://dashscope.aliyuncs.com/api-ws/v1/inference", forKey: "byok.tts.qwen.baseURL")

        TTSActiveProvider.adoptShownProviderIfUnset("qwen", hasCredential: true, defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: "byok.tts.qwen.model"), "qwen-audio-3.0-tts-flash")
        XCTAssertEqual(defaults.string(forKey: "byok.tts.qwen.voice"), "loongeva_v3.6")
        XCTAssertEqual(defaults.string(forKey: "byok.tts.qwen.baseURL"), "wss://dashscope.aliyuncs.com/api-ws/v1/inference")
        XCTAssertEqual(defaults.string(forKey: "byok.tts.model"), "qwen-audio-3.0-tts-flash")
        XCTAssertEqual(defaults.string(forKey: "byok.tts.voice"), "loongeva_v3.6")
        XCTAssertEqual(defaults.string(forKey: "byok.tts.baseURL"), "wss://dashscope.aliyuncs.com/api-ws/v1/inference")
    }

    /// Merely opening a configured cloud card must not override an explicit local route. Leaving
    /// the provider unset also avoids recreating the contradictory dual state at the next launch.
    func testBackfillDoesNotOverrideExplicitLocalEnginePick() {
        let defaults = freshDefaults("explicit-engine-wins")
        defaults.set("qwen-audio-3.0-tts-flash", forKey: "byok.tts.qwen.model")
        defaults.set(TTSEngine.sherpaKokoroLocal.rawValue, forKey: TTSEngine.defaultsKey)

        TTSActiveProvider.adoptShownProviderIfUnset("qwen", hasCredential: true, defaults: defaults)

        XCTAssertNil(defaults.string(forKey: "byok.tts.provider"))
        XCTAssertEqual(TTSEngine.selected(defaults: defaults), .sherpaKokoroLocal)
    }

    /// Exact pre-fix/update shape: the old shared fields and the matching scoped profile survived,
    /// but both route pointers are absent. Launch reconciliation must recover the unique provider
    /// before the menu/overview asks `TTSEngine.selected` and persists both pointers.
    func testLaunchReconcileRestoresUniqueLegacyConfiguredProvider() {
        let defaults = freshDefaults("launch-legacy-config")
        defaults.set("qwen3-tts-flash", forKey: "byok.tts.model")
        defaults.set("wss://dashscope.aliyuncs.com/api-ws/v1/inference", forKey: "byok.tts.baseURL")
        defaults.set("qwen3-tts-flash", forKey: "byok.tts.qwen.model")
        defaults.set("wss://dashscope.aliyuncs.com/api-ws/v1/inference", forKey: "byok.tts.qwen.baseURL")
        defaults.set("mimo-v2.5-tts", forKey: "byok.tts.mimo.model")
        defaults.set("https://api.xiaomimimo.com/v1", forKey: "byok.tts.mimo.baseURL")

        TTSActiveProvider.reconcileAtLaunch(defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: "byok.tts.provider"), "qwen")
        XCTAssertEqual(defaults.string(forKey: TTSEngine.defaultsKey), TTSEngine.cloudQwen.rawValue)
        XCTAssertEqual(TTSEngine.selected(defaults: defaults), .cloudQwen)
    }

    func testLaunchReconcilePersistsTheRetiredDoubaoCompatibilityRoute() {
        let defaults = freshDefaults("launch-retired-doubao")
        defaults.set("cloud-doubao", forKey: TTSEngine.defaultsKey)

        TTSActiveProvider.reconcileAtLaunch(defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: "byok.tts.provider"), "qwen")
        XCTAssertEqual(defaults.string(forKey: TTSEngine.defaultsKey), TTSEngine.cloudQwen.rawValue)
    }

    /// Newer partial state: active provider exists but the engine pointer does not. Restore the
    /// engine and copy the provider-scoped values instead of resetting them to catalog defaults.
    func testLaunchReconcileRestoresEngineFromActiveProviderWithoutResettingConfig() {
        let defaults = freshDefaults("launch-provider-only")
        defaults.set("mimo", forKey: "byok.tts.provider")
        defaults.set("custom-mimo-tts", forKey: "byok.tts.mimo.model")
        defaults.set("Mia", forKey: "byok.tts.mimo.voice")

        TTSActiveProvider.reconcileAtLaunch(defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: TTSEngine.defaultsKey), TTSEngine.cloudMimo.rawValue)
        XCTAssertEqual(defaults.string(forKey: "byok.tts.model"), "custom-mimo-tts")
        XCTAssertEqual(defaults.string(forKey: "byok.tts.voice"), "Mia")
    }

    /// Existing explicit routes remain authoritative. Reconciliation repairs the provider/config
    /// side to the selected cloud engine rather than letting an unrelated card override the route.
    func testLaunchReconcileRepairsProviderToExplicitCloudEngine() {
        let defaults = freshDefaults("launch-engine-wins")
        defaults.set(TTSEngine.cloudMimo.rawValue, forKey: TTSEngine.defaultsKey)
        defaults.set("qwen", forKey: "byok.tts.provider")
        defaults.set("custom-mimo-tts", forKey: "byok.tts.mimo.model")

        TTSActiveProvider.reconcileAtLaunch(defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: "byok.tts.provider"), "mimo")
        XCTAssertEqual(defaults.string(forKey: "byok.tts.model"), "custom-mimo-tts")
        XCTAssertEqual(defaults.string(forKey: TTSEngine.defaultsKey), TTSEngine.cloudMimo.rawValue)
    }

    /// Older installs could have a coherent route while keeping customized runtime values only
    /// in the shared active keys. Reconciliation must migrate those values into the matching
    /// provider profile before catalog fallbacks can replace them.
    func testLaunchReconcileMigratesLegacyActiveConfigForMatchingProvider() {
        let defaults = freshDefaults("launch-migrate-active-config")
        defaults.set(TTSEngine.cloudMimo.rawValue, forKey: TTSEngine.defaultsKey)
        defaults.set("mimo", forKey: "byok.tts.provider")
        defaults.set("legacy-custom-model", forKey: "byok.tts.model")
        defaults.set("LegacyVoice", forKey: "byok.tts.voice")
        defaults.set("https://tts.example.com/v1", forKey: "byok.tts.baseURL")

        TTSActiveProvider.reconcileAtLaunch(defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: "byok.tts.model"), "legacy-custom-model")
        XCTAssertEqual(defaults.string(forKey: "byok.tts.voice"), "LegacyVoice")
        XCTAssertEqual(defaults.string(forKey: "byok.tts.baseURL"), "https://tts.example.com/v1")
        XCTAssertEqual(defaults.string(forKey: "byok.tts.mimo.model"), "legacy-custom-model")
        XCTAssertEqual(defaults.string(forKey: "byok.tts.mimo.voice"), "LegacyVoice")
        XCTAssertEqual(defaults.string(forKey: "byok.tts.mimo.baseURL"), "https://tts.example.com/v1")
    }

    /// Multiple matching archived profiles are not enough evidence of the user's active route.
    /// The migration must leave both pointers unset instead of choosing by catalog order.
    func testLaunchReconcileDoesNotGuessWhenLegacyConfigIsAmbiguous() {
        let defaults = freshDefaults("launch-ambiguous")
        defaults.set("custom-shared-model", forKey: "byok.tts.model")
        defaults.set("custom-shared-model", forKey: "byok.tts.qwen.model")
        defaults.set("custom-shared-model", forKey: "byok.tts.mimo.model")

        TTSActiveProvider.reconcileAtLaunch(defaults: defaults)

        XCTAssertNil(defaults.string(forKey: "byok.tts.provider"))
        XCTAssertNil(defaults.string(forKey: TTSEngine.defaultsKey))
        XCTAssertEqual(TTSEngine.selected(defaults: defaults), .sherpaKokoroLocal)
    }

    private func freshDefaults(_ suffix: String) -> UserDefaults {
        let name = "TTSActiveProviderTests.\(suffix)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
