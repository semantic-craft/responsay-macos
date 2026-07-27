import XCTest
@testable import ResponsayMac

final class CapabilitySelectionSyncTests: XCTestCase {
    func testSwitchingLLMProviderSeedsThatProvidersDefaults() {
        let defaults = freshDefaults("llm")
        defaults.set("mimo", forKey: "byok.llm.provider")
        defaults.set("mimo-v2.5-pro", forKey: "byok.llm.model")
        defaults.set("https://token-plan-cn.xiaomimimo.com/v1", forKey: "byok.llm.baseURL")

        CapabilitySelectionSync.selectProvider("openai", capability: .llm, defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: "byok.llm.provider"), "openai")
        XCTAssertEqual(defaults.string(forKey: "byok.llm.model"), "chat-latest")  // 7d02e454
        XCTAssertEqual(defaults.string(forKey: "byok.llm.baseURL"), "https://api.openai.com/v1")
    }

    func testSelectingQwenSeedsPayAsYouGoDefaults() {
        let defaults = freshDefaults("qwen-payg")
        defaults.set("openai", forKey: "byok.llm.provider")
        defaults.set("gpt-5.5", forKey: "byok.llm.model")
        defaults.set("https://api.openai.com/v1", forKey: "byok.llm.baseURL")

        CapabilitySelectionSync.selectProvider("qwen", capability: .llm, defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: "byok.llm.provider"), "qwen")
        XCTAssertEqual(defaults.string(forKey: "byok.llm.plan"), BillingPlan.payg.rawValue)
        XCTAssertEqual(defaults.string(forKey: "byok.llm.model"), "qwen3.6-flash")
        XCTAssertEqual(defaults.string(forKey: "byok.llm.baseURL"), "https://dashscope.aliyuncs.com/compatible-mode/v1")
    }

    // (Token Plan is now the package billing plan inside `qwen`, picked in the card's 接入点
    // dropdown — not a separate provider selection; covered by ProviderConfigDispatcherTests.)

    func testReselectingSameTTSProviderPreservesEditedModelAndVoice() {
        let defaults = freshDefaults("tts")
        defaults.set("mimo", forKey: "byok.tts.provider")
        defaults.set("custom-mimo-model", forKey: "byok.tts.model")
        defaults.set("Mia", forKey: "byok.tts.voice")

        CapabilitySelectionSync.selectProvider("mimo", capability: .tts, defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: "byok.tts.model"), "custom-mimo-model")
        XCTAssertEqual(defaults.string(forKey: "byok.tts.voice"), "Mia")
    }

    func testASRProviderMatchUsesCanonicalLegacyIds() {
        let defaults = freshDefaults("asr")
        defaults.set("mimo-token-plan", forKey: "byok.asr.provider")
        defaults.set("mimo-v2.5-asr", forKey: "byok.asr.model")

        CapabilitySelectionSync.selectProvider("mimo", capability: .asr, defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: "byok.asr.provider"), "mimo")
        XCTAssertEqual(defaults.string(forKey: "byok.asr.model"), "mimo-v2.5-asr")
    }

    // MiMo ASR now supports 按量付费 — reselecting the same provider must PRESERVE a stored
    // payg endpoint (no more forced rewrite to Token Plan).
    func testReselectingMimoASRPreservesPayAsYouGoEndpoint() {
        let defaults = freshDefaults("mimo-asr-route")
        defaults.set("mimo", forKey: "byok.asr.provider")
        defaults.set(BillingPlan.payg.rawValue, forKey: "byok.asr.plan")
        defaults.set("https://api.xiaomimimo.com/v1", forKey: "byok.asr.baseURL")
        defaults.set("custom-mimo-asr", forKey: "byok.asr.model")

        CapabilitySelectionSync.selectProvider("mimo", capability: .asr, defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: "byok.asr.provider"), "mimo")
        XCTAssertEqual(defaults.string(forKey: "byok.asr.plan"), BillingPlan.payg.rawValue)
        XCTAssertEqual(defaults.string(forKey: "byok.asr.baseURL"), "https://api.xiaomimimo.com/v1")
        XCTAssertEqual(defaults.string(forKey: "byok.asr.model"), "custom-mimo-asr")
    }

    private func freshDefaults(_ suffix: String) -> UserDefaults {
        let name = "CapabilitySelectionSyncTests.\(suffix)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
