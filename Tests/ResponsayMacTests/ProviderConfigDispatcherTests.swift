import XCTest
import ResponsayCore
@testable import ResponsayMac

/// 233 — `ProviderConfigDispatcher` is the *consumer* the BYOK settings pane was missing:
/// it resolves what `CapabilityCardView` persisted (per-capability provider/region/plan/model/
/// baseURL in UserDefaults + the key in `BYOKKeychain`) into one concrete config, falling
/// back to `ProviderCatalog` defaults so an untouched install still resolves. Pure given the
/// injected defaults + key-reader, so it tests without the real Keychain or app launch.
final class ProviderConfigDispatcherTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "test.providerConfigDispatcher"

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

    private func dispatcher(keys: [String: String] = [:]) -> ProviderConfigDispatcher {
        ProviderConfigDispatcher(defaults: defaults, keyReader: { keys[$0] })
    }

    // MARK: Defaults (no stored selection → catalog default = 阿里云百炼 PAYG)

    func testLLMDefaultsToQwenPayAsYouGoValues() {
        let config = dispatcher().resolve(.llm)
        XCTAssertEqual(config.providerId, "qwen")
        XCTAssertEqual(config.region, .china)
        XCTAssertEqual(config.plan, .payg)
        XCTAssertEqual(config.model, "qwen3.6-flash")
        XCTAssertEqual(config.baseURL, "https://dashscope.aliyuncs.com/compatible-mode/v1")
    }

    /// Qwen3-ASR-Flash realtime is the sole Aliyun ASR route.
    func testASRDefaultUsesQwenASRFlashModel() {
        XCTAssertEqual(dispatcher().resolve(.asr).providerId, "qwen-asr-flash")
        XCTAssertEqual(dispatcher().resolve(.asr).model, QwenRealtimeEndpoint.defaultModel)
    }

    func testQwenASRUsesOnlyItsCurrentCredentialSlot() {
        XCTAssertEqual(
            dispatcher(keys: ["byok.qwen-asr-flash": "dashscope-key"])
                .resolve(.asr, providerId: "qwen-asr-flash").apiKey,
            "dashscope-key")
        XCTAssertNil(
            dispatcher(keys: ["byok.qwen-fun-asr": "retired-key"])
                .resolve(.asr, providerId: "qwen-asr-flash").apiKey)
    }

    func testQwenRealtimeIgnoresStaleStoredModelAndEndpoint() {
        defaults.set("qwen-asr-flash", forKey: "byok.asr.provider")
        defaults.set("qwen3-asr-flash-realtime", forKey: "byok.asr.model")
        defaults.set("wss://stale.example.com/realtime", forKey: "byok.asr.baseURL")

        let config = dispatcher().resolve(.asr)

        XCTAssertEqual(config.model, QwenRealtimeEndpoint.defaultModel)
        XCTAssertEqual(config.baseURL, "wss://dashscope.aliyuncs.com/api-ws/v1/realtime")
    }

    func testVolcengineFlashASRDefaultsToOfficialEndpointAndModel() {
        let config = dispatcher(keys: ["byok.volcengine-flash": "volc-app-key"])
            .resolve(.asr, providerId: "volcengine-flash")

        XCTAssertEqual(config.providerId, "volcengine-flash")
        XCTAssertEqual(config.region, .china)
        XCTAssertEqual(config.plan, .payg)
        // 豆包流式2.0 双向流式优化版 WSS endpoint (the realtime engine hardcodes it; this is the card copy).
        XCTAssertEqual(config.baseURL, "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_nostream")
        XCTAssertEqual(config.model, "bigmodel")
        XCTAssertEqual(config.apiKey, "volc-app-key")
        XCTAssertNotEqual(config.model, "doubao-seed-2-0-lite-260428")
        XCTAssertNotEqual(config.model, "doubao-seed-2-0-lite-260215")
    }

    func testTTSDefaultUsesQwenTTSModel() {
        let config = dispatcher().resolve(.tts)
        XCTAssertEqual(config.model, "qwen-audio-3.0-tts-flash")
        XCTAssertEqual(config.baseURL, "wss://dashscope.aliyuncs.com/api-ws/v1/inference")
    }

    func testQwenTTSIgnoresRetiredStoredModelAndEndpoint() {
        defaults.set("qwen", forKey: "byok.tts.provider")
        defaults.set("qwen3-tts-flash-realtime", forKey: "byok.tts.model")
        defaults.set("https://dashscope.aliyuncs.com/api/v1", forKey: "byok.tts.baseURL")

        let config = dispatcher().resolve(.tts)

        XCTAssertEqual(config.model, "qwen-audio-3.0-tts-flash")
        XCTAssertEqual(config.baseURL, "wss://dashscope.aliyuncs.com/api-ws/v1/inference")
    }

    func testVolcengineASRAndTTSResolveOfficialEndpoints() {
        let asr = dispatcher(keys: ["byok.volcengine-flash": "volc-asr-key"])
            .resolve(.asr, providerId: "volcengine-flash")
        XCTAssertEqual(asr.baseURL, "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_nostream")
        XCTAssertEqual(asr.model, "bigmodel")
        XCTAssertEqual(asr.apiKey, "volc-asr-key")

        let tts = dispatcher(keys: [TTSCredential.keychainAccount(for: "volcengine-tts"): "volc-tts-key"])
            .resolve(.tts, providerId: "volcengine-tts")
        XCTAssertEqual(tts.baseURL, "https://openspeech.bytedance.com/api/v3")
        XCTAssertEqual(tts.model, "seed-tts-2.0")
        XCTAssertEqual(tts.apiKey, "volc-tts-key")
    }

    // MARK: Stored selection overrides

    func testStoredProviderOverrideResolvesThatProvidersEndpoint() {
        defaults.set("deepseek", forKey: "byok.llm.provider")
        let config = dispatcher().resolve(.llm)
        XCTAssertEqual(config.providerId, "deepseek")
        XCTAssertEqual(config.region, .global)
        XCTAssertEqual(config.baseURL, "https://api.deepseek.com/v1")
        XCTAssertEqual(config.model, "deepseek-v4-flash")
    }

    func testStoredRegionPicksTheRegionEndpoint() {
        // MiniMax is the surviving multi-region preset (china + intl); Kimi (the former
        // example) was removed. Same dispatcher behavior: a stored region picks that
        // region's endpoint.
        defaults.set("minimax", forKey: "byok.tts.provider")
        defaults.set(ProviderRegion.intl.rawValue, forKey: "byok.tts.region")
        XCTAssertEqual(
            dispatcher().resolve(.tts).baseURL,
            "https://api.minimax.io/v1")
    }

    func testMimoASRAndLLMUseTokenPlanEndpointWhileTTSKeepsPayAsYouGoDefault() {
        defaults.set("mimo", forKey: "byok.asr.provider")
        XCTAssertEqual(dispatcher().resolve(.asr).baseURL, "https://token-plan-cn.xiaomimimo.com/v1")
        XCTAssertEqual(dispatcher().resolve(.asr).plan, .package)

        defaults.set("mimo", forKey: "byok.llm.provider")
        XCTAssertEqual(dispatcher().resolve(.llm).baseURL, "https://token-plan-cn.xiaomimimo.com/v1")
        XCTAssertEqual(dispatcher().resolve(.llm).plan, .package)

        defaults.set("mimo", forKey: "byok.tts.provider")
        XCTAssertEqual(dispatcher().resolve(.tts).baseURL, "https://api.xiaomimimo.com/v1")
        XCTAssertEqual(dispatcher().resolve(.tts).plan, .payg)
    }

    // 按量付费 is now a billing plan inside the single `mimo` provider (not a separate
    // provider). Selecting mimo + payg resolves to the 开放平台 endpoint + mimo-v2.5.
    func testMiMoLLMPayAsYouGoPlanResolvesToOpenPlatformEndpoint() {
        defaults.set("mimo", forKey: "byok.llm.provider")
        defaults.set(BillingPlan.payg.rawValue, forKey: "byok.llm.plan")
        let config = dispatcher().resolve(.llm)
        XCTAssertEqual(config.providerId, "mimo")
        XCTAssertEqual(config.plan, .payg)
        XCTAssertEqual(config.baseURL, "https://api.xiaomimimo.com/v1")
        XCTAssertEqual(config.model, "mimo-v2.5")
    }

    // mimo defaults to Token Plan (preserves existing tp- configs).
    func testMiMoLLMDefaultsToTokenPlanEndpoint() {
        defaults.set("mimo", forKey: "byok.llm.provider")
        let config = dispatcher().resolve(.llm)
        XCTAssertEqual(config.plan, .package)
        XCTAssertEqual(config.baseURL, "https://token-plan-cn.xiaomimimo.com/v1")
    }

    // A retired `mimo-payg` selection canonicalizes onto `mimo` instead of falling back
    // to the global default; the empty-host authHeaders path still resolves to api-key.
    func testRetiredMiMoPaygSelectionCanonicalizesToMimo() {
        defaults.set("mimo-payg", forKey: "byok.llm.provider")
        XCTAssertEqual(dispatcher().resolve(.llm).providerId, "mimo")
        XCTAssertEqual(
            LLMProviderCapabilities.resolve(providerId: "mimo-payg", baseURLHost: "").authHeaderStyle,
            .apiKeyHeader("api-key"))
    }

    // MiMo ASR now honors 按量付费 (no more forced rewrite to Token Plan).
    func testMimoASRPayAsYouGoEndpointIsHonored() {
        defaults.set("mimo", forKey: "byok.asr.provider")
        defaults.set(BillingPlan.payg.rawValue, forKey: "byok.asr.plan")
        defaults.set("https://api.xiaomimimo.com/v1", forKey: "byok.asr.baseURL")

        let config = dispatcher().resolve(.asr)

        XCTAssertEqual(config.plan, .payg)
        XCTAssertEqual(config.baseURL, "https://api.xiaomimimo.com/v1")
    }

    func testQwenProviderResolvesPayAsYouGoEndpoint() {
        defaults.set("qwen", forKey: "byok.llm.provider")
        let config = dispatcher().resolve(.llm)
        XCTAssertEqual(config.providerId, "qwen")
        XCTAssertEqual(config.baseURL, "https://dashscope.aliyuncs.com/compatible-mode/v1")
        XCTAssertEqual(config.plan, .payg)
        XCTAssertEqual(config.model, "qwen3.6-flash")
    }

    func testRetiredQwenTokenPlanSelectionFallsBackToPayAsYouGo() {
        defaults.set("qwen", forKey: "byok.llm.provider")
        defaults.set(BillingPlan.package.rawValue, forKey: "byok.llm.plan")
        defaults.set(
            "https://token-plan.cn-beijing.maas.aliyuncs.com/compatible-mode/v1",
            forKey: "byok.llm.baseURL")
        let config = dispatcher(keys: ["byok.qwen": "dashscope-secret"]).resolve(.llm)

        XCTAssertEqual(config.providerId, "qwen")
        XCTAssertEqual(config.region, .china)
        XCTAssertEqual(config.plan, .payg)
        XCTAssertEqual(config.baseURL, "https://dashscope.aliyuncs.com/compatible-mode/v1")
        XCTAssertEqual(config.model, "qwen3.6-flash")
        XCTAssertEqual(config.apiKey, "dashscope-secret")
    }

    func testExplicitBaseURLAndModelWinOverCatalog() {
        defaults.set("qwen", forKey: "byok.llm.provider")
        defaults.set("https://my-proxy.internal/v1", forKey: "byok.llm.baseURL")
        defaults.set("qwen3.7-max", forKey: "byok.llm.model")
        let config = dispatcher().resolve(.llm)
        XCTAssertEqual(config.baseURL, "https://my-proxy.internal/v1")
        XCTAssertEqual(config.model, "qwen3.7-max")
    }

    func testProviderScopedConfigCanBePreparedWithoutSelectingThatProvider() {
        defaults.set("qwen", forKey: "byok.llm.provider")
        defaults.set("https://api.deepseek.com/v1", forKey: "byok.llm.deepseek.baseURL")
        defaults.set("deepseek-reasoner", forKey: "byok.llm.deepseek.model")

        XCTAssertEqual(dispatcher().resolve(.llm).providerId, "qwen")

        let deepseek = dispatcher().resolve(.llm, providerId: "deepseek")
        XCTAssertEqual(deepseek.providerId, "deepseek")
        XCTAssertEqual(deepseek.baseURL, "https://api.deepseek.com/v1")
        XCTAssertEqual(deepseek.model, "deepseek-reasoner")
    }

    func testProviderScopedConfigWinsWhenProviderBecomesActive() {
        defaults.set("deepseek", forKey: "byok.llm.provider")
        defaults.set("https://stale.example/v1", forKey: "byok.llm.baseURL")
        defaults.set("stale-model", forKey: "byok.llm.model")
        defaults.set("https://proxy.example/v1", forKey: "byok.llm.deepseek.baseURL")
        defaults.set("deepseek-chat", forKey: "byok.llm.deepseek.model")

        let config = dispatcher().resolve(.llm)

        XCTAssertEqual(config.providerId, "deepseek")
        XCTAssertEqual(config.baseURL, "https://proxy.example/v1")
        XCTAssertEqual(config.model, "deepseek-chat")
    }

    func testUnknownStoredProviderFallsBackToDefault() {
        defaults.set("does-not-exist", forKey: "byok.llm.provider")
        XCTAssertEqual(dispatcher().resolve(.llm).providerId, "qwen")
    }

    // Legacy provider ids canonicalize onto the surviving Qwen PAYG route.
    func testLegacyQwenTeamLLMSelectionCanonicalizesToQwen() {
        defaults.set("qwen-team", forKey: "byok.llm.provider")

        let config = dispatcher().resolve(.llm)

        XCTAssertEqual(config.providerId, "qwen")
        XCTAssertEqual(config.plan, .payg)
        XCTAssertEqual(config.model, "qwen3.6-flash")
        XCTAssertEqual(config.baseURL, "https://dashscope.aliyuncs.com/compatible-mode/v1")
    }

    func testLegacyQwenTokenPlanProviderCanonicalizesToQwenPayAsYouGo() {
        defaults.set("qwen-token-plan", forKey: "byok.llm.provider")

        let config = dispatcher().resolve(.llm)

        XCTAssertEqual(config.providerId, "qwen")
        XCTAssertEqual(config.plan, .payg)
        XCTAssertEqual(config.baseURL, "https://dashscope.aliyuncs.com/compatible-mode/v1")
    }

    func testDoubaoLLMDefaultsToArkSeedTurboEndpointAndModel() {
        let config = dispatcher(keys: ["byok.doubao": "ark-test-key"])
            .resolve(.llm, providerId: "doubao")

        XCTAssertEqual(config.providerId, "doubao")
        XCTAssertEqual(config.region, .china)
        XCTAssertEqual(config.plan, .payg)
        XCTAssertEqual(config.model, "doubao-seed-2-1-turbo-260628")
        XCTAssertEqual(config.baseURL, "https://ark.cn-beijing.volces.com/api/v3")
        XCTAssertEqual(config.apiKey, "ark-test-key")
        XCTAssertNotEqual(config.model, "bigmodel")
    }

    // MARK: Keys

    func testKeyIsReadFromKeychainByProviderId() {
        let config = dispatcher(keys: ["byok.qwen": "dashscope-secret"]).resolve(.llm)
        XCTAssertEqual(config.apiKey, "dashscope-secret")
        XCTAssertTrue(config.hasKey)
    }

    func testQwenPayAsYouGoReadsLegacyMultiPlanKeySlot() {
        let config = dispatcher(keys: ["byok.qwen.payg": "legacy-dashscope-secret"]).resolve(.llm)
        XCTAssertEqual(config.apiKey, "legacy-dashscope-secret")
    }

    func testMultiPlanProviderStoresKeyPerPlanSinglePlanStaysShared() {
        // 按量付费 (sk-) and Token Plan (tp-) keep separate keychain slots for a multi-plan
        // provider, so neither overwrites the other; single-plan providers keep one slot.
        XCTAssertEqual(
            CapabilityCredentialAccount.apiKeyAccount(providerId: "mimo", capability: .asr, plan: .payg),
            "byok.mimo.payg")
        XCTAssertEqual(
            CapabilityCredentialAccount.apiKeyAccount(providerId: "mimo", capability: .asr, plan: .package),
            "byok.mimo.package")
        XCTAssertEqual(
            CapabilityCredentialAccount.apiKeyAccount(providerId: "mimo", capability: .tts, plan: .package),
            "byok.tts.mimo.package")
        XCTAssertEqual(
            CapabilityCredentialAccount.apiKeyAccount(providerId: "qwen", capability: .llm, plan: .payg),
            "byok.qwen")
        // single-plan provider ignores the plan and keeps its shared slot
        XCTAssertEqual(
            CapabilityCredentialAccount.apiKeyAccount(providerId: "openai", capability: .llm, plan: .package),
            "byok.openai")
        XCTAssertEqual(
            CapabilityCredentialAccount.apiKeyAccount(providerId: "doubao", capability: .llm, plan: .package),
            "byok.doubao")

        // Dispatcher reads the slot for the resolved plan: payg key is invisible on Token Plan.
        defaults.set("mimo", forKey: "byok.llm.provider")
        defaults.set(BillingPlan.package.rawValue, forKey: "byok.llm.plan")
        XCTAssertFalse(dispatcher(keys: ["byok.mimo.payg": "sk-x"]).resolve(.llm).hasKey)
        XCTAssertTrue(dispatcher(keys: ["byok.mimo.package": "tp-x"]).resolve(.llm).hasKey)
    }

    func testTTSKeyUsesDedicatedTTSCredentialNamespace() {
        defaults.set("qwen", forKey: "byok.tts.provider")
        let config = dispatcher(keys: [
            TTSCredential.keychainAccount(for: "qwen"): "tts-secret",
            TTSCredential.coachAccount(for: "qwen"): "shared-secret",
        ]).resolve(.tts)

        XCTAssertEqual(config.apiKey, "tts-secret")
        XCTAssertTrue(config.hasKey)
    }

    func testSettingsCardWritesTTSKeysToDedicatedNamespace() {
        XCTAssertEqual(
            CapabilityCredentialAccount.apiKeyAccount(providerId: "qwen", capability: .tts),
            TTSCredential.keychainAccount(for: "qwen"))
        XCTAssertEqual(
            CapabilityCredentialAccount.apiKeyAccount(providerId: "qwen", capability: .llm),
            TTSCredential.coachAccount(for: "qwen"))
        XCTAssertEqual(
            CapabilityCredentialAccount.apiKeyAccount(providerId: "qwen", capability: .asr),
            TTSCredential.coachAccount(for: "qwen"))
        XCTAssertEqual(
            CapabilityCredentialAccount.apiKeyAccount(providerId: "volcengine-tts", capability: .tts),
            TTSCredential.keychainAccount(for: "volcengine-tts"))
    }

    func testMimoASRAndLLMShareTokenPlanCredentialNamespace() {
        XCTAssertEqual(
            CapabilityCredentialAccount.apiKeyAccount(providerId: "mimo", capability: .asr),
            TTSCredential.coachAccount(for: "mimo"))
        XCTAssertEqual(
            CapabilityCredentialAccount.apiKeyAccount(providerId: "mimo", capability: .llm),
            TTSCredential.coachAccount(for: "mimo"))
        XCTAssertEqual(
            CapabilityCredentialAccount.apiKeyAccount(providerId: "mimo", capability: .tts),
            TTSCredential.keychainAccount(for: "mimo"))
    }

    func testMissingKeyMeansNoKey() {
        XCTAssertNil(dispatcher().resolve(.llm).apiKey)
        XCTAssertFalse(dispatcher().resolve(.llm).hasKey)
    }

    func testLocalProviderNeverCarriesAKey() {
        defaults.set("apple", forKey: "byok.asr.provider")
        let config = dispatcher(keys: ["byok.apple": "should-be-ignored"]).resolve(.asr)
        XCTAssertNil(config.apiKey)
    }

    // Backend BYOK header bridge (byokHeaders / byokHeaderName) removed with the launch-time
    // keyHeaderProvider seam — see issue 332.
}
