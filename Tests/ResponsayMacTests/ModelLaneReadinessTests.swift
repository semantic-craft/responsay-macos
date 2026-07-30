import XCTest
import ResponsayCore
@testable import ResponsayMac

/// 378/379/382 — readiness of a model option (a menu choice or the current selection)
/// is the single source for the 设置·模型 pills, the menu-bar jump-to-config decision,
/// and the overview status strip. Local engines are always ready (no key); cloud
/// engines are ready iff a BYOK key exists. Pure given an injected dispatcher + OCR
/// key reader, so it tests without the real Keychain.
final class ModelLaneReadinessTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "test.modelLaneReadiness"

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

    private func resolver(
        keys: [String: String] = [:],
        ocrKeys: [String: String] = [:],
        asrLocalInstalled: Bool = false,
        ttsLocalInstalled: Bool = false,
        ocrLocalInstalled: Bool = false
    ) -> ModelLaneReadinessResolver {
        ModelLaneReadinessResolver(
            dispatcher: ProviderConfigDispatcher(defaults: defaults, keyReader: { keys[$0] }),
            ocrKeyReader: { ocrKeys[$0] },
            asrLocalInstalled: { _ in asrLocalInstalled },
            ttsLocalInstalled: { ttsLocalInstalled },
            ocrLocalInstalled: { ocrLocalInstalled })
    }

    // MARK: - LLM lane
    // (offline/Ollama LLM lane removed in ade8fcf6 — testLLMOfflineIsLocal deleted with it.)

    func testLLMCloudWithKeyIsReady() {
        let account = CapabilityCredentialAccount.apiKeyAccount(providerId: "openai", capability: .llm)
        XCTAssertEqual(resolver(keys: [account: "sk-test"]).llm(optionId: "openai"), .cloudReady)
    }

    func testLLMCloudWithoutKeyIsUnconfigured() {
        XCTAssertEqual(resolver().llm(optionId: "openai"), .cloudUnconfigured)
    }

    func testReadinessIsPerPlanForMultiPlanProvider() {
        // 按量付费 key on file, Token Plan slot empty → only the payg entry reads as ready, so
        // the menu filter shows just "小米Mimo · 按量付费".
        let paygAccount = CapabilityCredentialAccount.apiKeyAccount(providerId: "mimo", capability: .llm, plan: .payg)
        let r = resolver(keys: [paygAccount: "sk-x"])
        XCTAssertEqual(r.llm(optionId: "mimo#payg"), .cloudReady)
        XCTAssertEqual(r.llm(optionId: "mimo#package"), .cloudUnconfigured)
    }

    // MARK: - ASR lane

    func testASRAppleIsReadyWithoutDownloadedModel() {
        XCTAssertEqual(resolver().asr(optionId: "apple"), .local)
    }

    func testASRDownloadedEngineIsNotReadyWhenModelIsMissing() {
        XCTAssertEqual(resolver().asr(optionId: "offline-sensevoice"), .localNotInstalled)
        XCTAssertEqual(
            resolver(asrLocalInstalled: true).asr(optionId: "offline-sensevoice"),
            .local)
    }

    func testASRCloudWithKeyIsReady() {
        let account = CapabilityCredentialAccount.apiKeyAccount(providerId: "openai", capability: .asr)
        XCTAssertEqual(resolver(keys: [account: "sk-test"]).asr(optionId: "cloud-openai"), .cloudReady)
    }

    func testVolcengineFlashASRWithKeyIsReady() {
        let account = CapabilityCredentialAccount.apiKeyAccount(providerId: "volcengine-flash", capability: .asr)
        XCTAssertEqual(
            resolver(keys: [account: "volc-app-key"]).asr(optionId: "cloud-volcengine-flash"),
            .cloudReady)
    }

    func testASRCloudWithoutKeyIsUnconfigured() {
        XCTAssertEqual(resolver().asr(optionId: "cloud-openai"), .cloudUnconfigured)
    }

    // MARK: - TTS lane

    func testTTSLocalEngineIsNotReadyWhenModelIsMissing() {
        XCTAssertEqual(
            resolver().tts(optionId: TTSEngine.sherpaKokoroLocal.rawValue),
            .localNotInstalled)
        XCTAssertEqual(
            resolver(ttsLocalInstalled: true).tts(optionId: TTSEngine.sherpaKokoroLocal.rawValue),
            .local)
    }

    func testTTSCloudWithKeyIsReady() {
        let account = CapabilityCredentialAccount.apiKeyAccount(providerId: "openai", capability: .tts)
        XCTAssertEqual(resolver(keys: [account: "sk-test"]).tts(optionId: TTSEngine.cloudOpenAI.rawValue), .cloudReady)
    }

    func testTTSCloudWithoutKeyIsUnconfigured() {
        XCTAssertEqual(resolver().tts(optionId: TTSEngine.cloudOpenAI.rawValue), .cloudUnconfigured)
    }

    func testCloudKeyDoesNotHideInvalidEndpoint() {
        defaults.set("custom", forKey: "byok.llm.provider")
        defaults.set(
            "not-a-url",
            forKey: CapabilityProviderConfigStore.scopedKey(
                "baseURL", providerId: "custom", capability: .llm))
        defaults.set(
            "my-model",
            forKey: CapabilityProviderConfigStore.scopedKey(
                "model", providerId: "custom", capability: .llm))
        let account = CapabilityCredentialAccount.apiKeyAccount(
            providerId: "custom", capability: .llm)

        XCTAssertEqual(
            resolver(keys: [account: "sk-test"]).llm(optionId: "custom"),
            .cloudUnconfigured)
    }

    func testCloudKeyDoesNotHideMissingModel() {
        defaults.set("custom", forKey: "byok.llm.provider")
        defaults.set(
            "https://example.com/v1",
            forKey: CapabilityProviderConfigStore.scopedKey(
                "baseURL", providerId: "custom", capability: .llm))
        let account = CapabilityCredentialAccount.apiKeyAccount(
            providerId: "custom", capability: .llm)

        XCTAssertEqual(
            resolver(keys: [account: "sk-test"]).llm(optionId: "custom"),
            .cloudUnconfigured)
    }

    // MARK: - OCR lane

    func testOCRAppleVisionIsLocal() {
        XCTAssertEqual(resolver().ocr(optionId: OCREngine.appleVision.rawValue), .local)
    }

    func testOCRPaddleNeedsInstalledModel() {
        XCTAssertEqual(
            resolver(ocrLocalInstalled: false).ocr(optionId: OCREngine.paddleOCRLocal.rawValue),
            .localNotInstalled)
        XCTAssertEqual(
            resolver(ocrLocalInstalled: true).ocr(optionId: OCREngine.paddleOCRLocal.rawValue),
            .local)
    }

    func testOCRMistralWithKeyIsReady() {
        XCTAssertEqual(
            resolver(ocrKeys: [OCRCredentialAccount.mistralAPIKey: "sk-test"]).ocr(optionId: OCREngine.mistral.rawValue),
            .cloudReady)
    }

    func testOCRMistralWithoutKeyIsUnconfigured() {
        XCTAssertEqual(resolver().ocr(optionId: OCREngine.mistral.rawValue), .cloudUnconfigured)
    }

    func testOCRBaiduNeedsBothKeys() {
        // Only the API key, not the secret → still unconfigured.
        XCTAssertEqual(
            resolver(ocrKeys: [OCRCredentialAccount.baiduAPIKey: "k"]).ocr(optionId: OCREngine.baidu.rawValue),
            .cloudUnconfigured)
        XCTAssertEqual(
            resolver(ocrKeys: [
                OCRCredentialAccount.baiduAPIKey: "k",
                OCRCredentialAccount.baiduSecretKey: "s",
            ]).ocr(optionId: OCREngine.baidu.rawValue),
            .cloudReady)
    }

    // MARK: - Convenience flags

    func testReadinessFlags() {
        XCTAssertTrue(ModelLaneReadiness.local.isReady)
        XCTAssertTrue(ModelLaneReadiness.cloudReady.isReady)
        XCTAssertFalse(ModelLaneReadiness.localNotInstalled.isReady)
        XCTAssertFalse(ModelLaneReadiness.cloudUnconfigured.isReady)
        XCTAssertTrue(ModelLaneReadiness.localNotInstalled.needsConfiguration)
        XCTAssertTrue(ModelLaneReadiness.cloudUnconfigured.needsConfiguration)
        XCTAssertFalse(ModelLaneReadiness.local.needsConfiguration)
    }
}
