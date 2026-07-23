import XCTest
import ResponsayCore
@testable import ResponsayMac

/// 378/382 — `ModelLaneDisplay` is the single snapshot the 设置·模型 panel and the
/// overview status strip both render from. Verifies it reads the saved selection per
/// lane and wires readiness + jump target through. Pure given injected defaults + key reader.
final class ModelLaneDisplayTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "test.modelLaneDisplay"

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

    private func display(
        keys: [String: String] = [:],
        ocrKeys: [String: String] = [:],
        ocrLocalInstalled: Bool = false
    ) -> ModelLaneDisplay {
        ModelLaneDisplay(
            defaults: defaults,
            readiness: ModelLaneReadinessResolver(
                dispatcher: ProviderConfigDispatcher(defaults: defaults, keyReader: { keys[$0] }),
                ocrKeyReader: { ocrKeys[$0] },
                ocrLocalInstalled: { ocrLocalInstalled }))
    }

    func testFourLanesInOrder() {
        XCTAssertEqual(display().lanes().map(\.lane), [.asr, .llm, .tts, .ocr])
    }

    func testEachLaneJumpsToItsOwnConfigSection() {
        let byLane = Dictionary(uniqueKeysWithValues: display().lanes().map { ($0.lane, $0.settingsSection) })
        XCTAssertEqual(byLane[.asr], .asr)
        XCTAssertEqual(byLane[.llm], .llm)
        XCTAssertEqual(byLane[.tts], .tts)
        XCTAssertEqual(byLane[.ocr], .ocr)
    }

    func testASRReflectsStoredEngineAndLocalBadge() {
        defaults.set("offline-sensevoice", forKey: ASREngine.defaultsKey)
        let asr = display().lanes().first { $0.lane == .asr }!
        XCTAssertEqual(asr.currentOptionId, "offline-sensevoice")
        XCTAssertTrue(asr.isLocal)
        XCTAssertEqual(asr.badge, "本机")
        XCTAssertEqual(asr.readiness, .local)
    }

    func testLLMCloudUnconfiguredVsReady() {
        defaults.set("openai", forKey: "byok.llm.provider")

        let unconfigured = display().lanes().first { $0.lane == .llm }!
        XCTAssertEqual(unconfigured.currentOptionId, "openai")
        XCTAssertFalse(unconfigured.isLocal)
        XCTAssertEqual(unconfigured.readiness, .cloudUnconfigured)

        let account = CapabilityCredentialAccount.apiKeyAccount(providerId: "openai", capability: .llm)
        let ready = display(keys: [account: "sk-test"]).lanes().first { $0.lane == .llm }!
        XCTAssertEqual(ready.readiness, .cloudReady)
    }

    // Regression: a plan-tagged ASR selection ("cloud-mimo#package") must still resolve to the
    // cloud MiMo engine. Before the parse fix, the "#package" suffix broke ASREngine.fromStoredValue,
    // so the lane fell back to local Apple — showing 模型 ID "apple" / 本机 for a selected cloud engine.
    func testASRMiMoPlanTaggedShowsCloudModelNotAppleFallback() {
        defaults.set(ASREngine.cloudMimo.rawValue, forKey: ASREngine.defaultsKey)
        defaults.set("mimo", forKey: "byok.asr.provider")
        let asr = display().lanes().first { $0.lane == .asr }!
        XCTAssertTrue(asr.currentOptionId.hasPrefix("cloud-mimo"))
        XCTAssertFalse(asr.isLocal, "MiMo ASR must read as cloud, not fall back to local Apple")
        XCTAssertEqual(asr.badge, "云端")
        XCTAssertEqual(asr.modelId, "mimo-v2.5-asr", "must show MiMo's model id, not \"apple\"")
    }

    // Regression: a plan-tagged LLM selection ("mimo#package") must still resolve the preset +
    // model. Before the parse fix, the "#package" suffix failed the preset lookup, so the model id
    // fell back to the literal "默认模型".
    func testLLMMiMoPlanTaggedShowsModelNotDefault() {
        defaults.set("mimo", forKey: "byok.llm.provider")
        let llm = display().lanes().first { $0.lane == .llm }!
        XCTAssertFalse(llm.isLocal)
        XCTAssertEqual(llm.modelId, "mimo-v2.5", "must show MiMo's model id, not the literal \"默认模型\"")
        XCTAssertNotEqual(llm.currentTitle, "自定义 OpenAI 兼容", "preset must resolve from the base id")
    }

    func testOCRReflectsStoredEngine() {
        defaults.set("mistral-ocr", forKey: OCREngine.defaultsKey)
        let ocr = display().lanes().first { $0.lane == .ocr }!
        XCTAssertEqual(ocr.currentOptionId, "mistral-ocr")
        XCTAssertFalse(ocr.isLocal)
        XCTAssertEqual(ocr.readiness, .cloudUnconfigured)
    }

    func testOCRPaddleShowsLocalModelState() {
        defaults.set(OCREngine.paddleOCRLocal.rawValue, forKey: OCREngine.defaultsKey)
        let missing = display(ocrLocalInstalled: false).lanes().first { $0.lane == .ocr }!
        XCTAssertEqual(missing.currentOptionId, PaddleOCRProvider.engineID)
        XCTAssertTrue(missing.isLocal)
        XCTAssertEqual(missing.badge, "本机")
        XCTAssertEqual(missing.modelId, LocalModelRegistry.defaultOCR.id)
        XCTAssertEqual(missing.readiness, .localNotInstalled)

        let ready = display(ocrLocalInstalled: true).lanes().first { $0.lane == .ocr }!
        XCTAssertEqual(ready.readiness, .local)
    }
}
