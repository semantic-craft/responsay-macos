import XCTest
import ResponsayCore
@testable import ResponsayMac

/// #572 — providers measured unable to hold the strict plan contract stop at the capability
/// gate before any request is sent (capsule: "当前模型不支持", not a retryable blocked card).
final class IntentPlanProviderGateTests: XCTestCase {

    private func endpoint(providerId: String, baseURL: String) -> LLMEndpoint {
        LLMEndpoint(
            providerId: providerId, baseURL: baseURL, model: "test-model",
            apiKey: "sk-test", thinkingEnabled: false)
    }

    func testGateListIsEmpty_miMoUngatedAfterPromptV6() {
        // #575: mimo measured 96% auto-insert / zero wrong-text on the v6 prompt — un-gated.
        // The mechanism stays for future non-conformant providers (list-driven).
        XCTAssertFalse(SettingsBackedIntentPlanCompiler.isUnsupportedPlanProvider(
            endpoint(providerId: "mimo", baseURL: "https://token-plan-cn.xiaomimimo.com/v1")))
        XCTAssertFalse(SettingsBackedIntentPlanCompiler.isUnsupportedPlanProvider(
            endpoint(providerId: "mimo-payg", baseURL: "https://api.xiaomimimo.com/v1")))
        XCTAssertTrue(SettingsBackedIntentPlanCompiler.unsupportedPlanProviders.isEmpty)
    }

    func testConformantProvidersPassTheGate() {
        XCTAssertFalse(SettingsBackedIntentPlanCompiler.isUnsupportedPlanProvider(
            endpoint(providerId: "deepseek", baseURL: "https://api.deepseek.com/v1")))
        XCTAssertFalse(SettingsBackedIntentPlanCompiler.isUnsupportedPlanProvider(
            endpoint(providerId: "qwen", baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1")))
    }
}
