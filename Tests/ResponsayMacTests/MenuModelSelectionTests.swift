import XCTest
import ResponsayCore
@testable import ResponsayMac

/// 379 — the menu-bar quick picker jumps to config only when the chosen model is an
/// unconfigured cloud model; local / already-keyed models switch silently (nil section).
final class MenuModelSelectionTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "test.menuModelSelection"

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

    private func resolver(keys: [String: String] = [:]) -> ModelLaneReadinessResolver {
        ModelLaneReadinessResolver(
            dispatcher: ProviderConfigDispatcher(defaults: defaults, keyReader: { keys[$0] }),
            ocrKeyReader: { _ in nil })
    }

    func testUnconfiguredCloudASRJumpsToASRConfig() {
        XCTAssertEqual(
            MenuModelSelection.sectionToConfigure(forASR: "cloud-openai", readiness: resolver()),
            .asr)
    }

    func testConfiguredCloudASRDoesNotJump() {
        let account = CapabilityCredentialAccount.apiKeyAccount(providerId: "openai", capability: .asr)
        XCTAssertNil(
            MenuModelSelection.sectionToConfigure(forASR: "cloud-openai", readiness: resolver(keys: [account: "k"])))
    }

    func testLocalASRDoesNotJump() {
        XCTAssertNil(MenuModelSelection.sectionToConfigure(forASR: "apple", readiness: resolver()))
    }

    func testUnconfiguredCloudLLMJumpsToLLMConfig() {
        XCTAssertEqual(
            MenuModelSelection.sectionToConfigure(forLLM: "openai", readiness: resolver()),
            .llm)
    }

    func testConfiguredCloudLLMDoesNotJump() {
        let account = CapabilityCredentialAccount.apiKeyAccount(providerId: "openai", capability: .llm)
        XCTAssertNil(
            MenuModelSelection.sectionToConfigure(forLLM: "openai", readiness: resolver(keys: [account: "k"])))
    }

    // (offline/Ollama LLM route removed in ade8fcf6 — testOfflineLLMDoesNotJump deleted with it.)

    func testUnconfiguredCloudTTSJumpsToTTSConfig() {
        XCTAssertEqual(
            MenuModelSelection.sectionToConfigure(forTTS: "cloud-minimax", readiness: resolver()),
            .tts)
    }

    func testConfiguredCloudTTSDoesNotJump() {
        let account = CapabilityCredentialAccount.apiKeyAccount(providerId: "minimax", capability: .tts)
        XCTAssertNil(
            MenuModelSelection.sectionToConfigure(forTTS: "cloud-minimax", readiness: resolver(keys: [account: "k"])))
    }

    // MARK: - configuredOptions (menu-bar shows configured providers only)

    private func visibleLLM(current: String, keys: [String: String] = [:]) -> [String] {
        let r = resolver(keys: keys)
        return MenuModelSelection.configuredOptions(
            ModelRouteCatalog.llmOptions, current: current, readiness: { r.llm(optionId: $0) }
        ).map(\.id)
    }

    private func visibleASR(current: String, keys: [String: String] = [:]) -> [String] {
        let r = resolver(keys: keys)
        return MenuModelSelection.configuredOptions(
            ModelRouteCatalog.asrOptions, current: current, readiness: { r.asr(optionId: $0) }
        ).map(\.id)
    }

    func testConfiguredOptionsHidesUnconfiguredCloud() {
        // No keys at all: unconfigured cloud LLM providers that aren't the current
        // selection are dropped from the menu. (Offline/Ollama route removed in ade8fcf6.)
        let visible = visibleLLM(current: "openai")
        XCTAssertFalse(visible.contains("deepseek"))
        XCTAssertFalse(visible.contains("qwen"))
    }

    func testConfiguredOptionsKeepsKeyedCloud() {
        let account = CapabilityCredentialAccount.apiKeyAccount(providerId: "deepseek", capability: .llm)
        let visible = visibleLLM(current: "offline", keys: [account: "k"])
        XCTAssertTrue(visible.contains("deepseek"))
        // a still-unconfigured sibling stays hidden
        XCTAssertFalse(visible.contains("zhipu"))
    }

    func testConfiguredOptionsAlwaysKeepsLocalEngines() {
        // Local ASR engines need no key and must never be filtered out.
        let visible = visibleASR(current: "apple")
        XCTAssertTrue(visible.contains("apple"))
        XCTAssertTrue(visible.contains(ASREngine.sensevoiceLocal.rawValue))
        XCTAssertTrue(visible.contains(ASREngine.qwen3LocalASR.rawValue))
        // unconfigured cloud ASR is dropped
        XCTAssertFalse(visible.contains("cloud-openai"))
    }

    func testConfiguredOptionsKeepsCurrentEvenWhenUnconfigured() {
        // The active route is always shown so the user can see what's on, even if its
        // key was cleared — but other unconfigured providers stay hidden.
        let visible = visibleLLM(current: "qwen")   // qwen has no key in this resolver
        XCTAssertTrue(visible.contains("qwen"))
        XCTAssertFalse(visible.contains("deepseek"))
    }

    // MARK: - Custom OpenAI-compatible provider end-to-end

    func testCustomLLMProviderAppearsOnceKeyed() {
        // Verifies the custom provider feature: a user who saved a key for 「自定义 OpenAI
        // 兼容」sees it in the quick picker; without a key it stays hidden.
        defaults.set(
            "https://my-host.example/v1",
            forKey: CapabilityProviderConfigStore.scopedKey(
                "baseURL", providerId: "custom", capability: .llm))
        defaults.set(
            "my-private-model",
            forKey: CapabilityProviderConfigStore.scopedKey(
                "model", providerId: "custom", capability: .llm))
        let account = CapabilityCredentialAccount.apiKeyAccount(providerId: "custom", capability: .llm)
        XCTAssertFalse(visibleLLM(current: "offline").contains("custom"))
        XCTAssertTrue(visibleLLM(current: "offline", keys: [account: "sk-user"]).contains("custom"))
    }

    func testCustomLLMResolvesStoredEndpointModelAndKey() {
        // The custom provider is functional end-to-end: its user-entered Base URL + model
        // + key resolve into a configured LLM endpoint (not the catalog default).
        defaults.set("custom", forKey: "byok.llm.provider")
        defaults.set("https://my-host.example/v1",
                     forKey: CapabilityProviderConfigStore.scopedKey("baseURL", providerId: "custom", capability: .llm))
        defaults.set("my-private-model",
                     forKey: CapabilityProviderConfigStore.scopedKey("model", providerId: "custom", capability: .llm))
        let account = CapabilityCredentialAccount.apiKeyAccount(providerId: "custom", capability: .llm)
        let dispatcher = ProviderConfigDispatcher(defaults: defaults, keyReader: { [account: "sk-user"][$0] })

        let cfg = dispatcher.resolve(.llm)
        XCTAssertEqual(cfg.providerId, "custom")
        XCTAssertEqual(cfg.baseURL, "https://my-host.example/v1")
        XCTAssertEqual(cfg.model, "my-private-model")
        XCTAssertEqual(cfg.apiKey, "sk-user")
        XCTAssertTrue(cfg.hasKey)

        let endpoint = LLMEndpointResolver.resolveCloud(defaults: defaults, dispatcher: dispatcher)
        XCTAssertNotNil(endpoint)
        XCTAssertEqual(endpoint?.baseURL, "https://my-host.example/v1")
        XCTAssertEqual(endpoint?.model, "my-private-model")
        XCTAssertTrue(endpoint?.isConfigured ?? false)
    }
}
