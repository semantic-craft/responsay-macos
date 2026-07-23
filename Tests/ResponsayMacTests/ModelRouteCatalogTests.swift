import XCTest
import ResponsayCore
@testable import ResponsayMac

/// Covers the shared ASR/LLM route catalog + the ASR selection action that the
/// menu-bar submenus and the main-panel quick picker both depend on.
final class ModelRouteCatalogTests: XCTestCase {

    // MARK: - applyASRSelection

    func testApplyASRSelectionCloudEngineSetsEngineAndSyncsProvider() {
        let defaults = freshDefaults("asr-cloud")

        ModelRouteSelectionActions.applyASRSelection("cloud-openai", defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: ASREngine.defaultsKey), "cloud-openai")
        XCTAssertEqual(defaults.string(forKey: "byok.asr.provider"), "openai")
    }

    func testApplyASRSelectionLocalEngineLeavesProviderUntouched() {
        let defaults = freshDefaults("asr-local")
        defaults.set("openai", forKey: "byok.asr.provider")

        ModelRouteSelectionActions.applyASRSelection("apple", defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: ASREngine.defaultsKey), "apple")
        // Local engines have no associated provider, so the BYOK provider is left as-is.
        XCTAssertEqual(defaults.string(forKey: "byok.asr.provider"), "openai")
    }

    func testApplyTTSSelectionCloudEngineSetsEngineAndSyncsProvider() {
        let defaults = freshDefaults("tts-cloud")

        ModelRouteSelectionActions.applyTTSSelection("cloud-minimax", defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: TTSEngine.defaultsKey), "cloud-minimax")
        XCTAssertEqual(defaults.string(forKey: "byok.tts.provider"), "minimax")
    }

    // MARK: - currentASRId

    func testCurrentASRIdReflectsStoredEngine() {
        let defaults = freshDefaults("asr-current")
        defaults.set("cloud-openai", forKey: ASREngine.defaultsKey)

        XCTAssertEqual(ModelRouteCatalog.currentASRId(defaults: defaults), "cloud-openai")
    }

    func testCurrentASRIdFallsBackWhenRetiredEngineIsGone() {
        let defaults = freshDefaults("asr-retired")
        defaults.set("cloud-qwen", forKey: ASREngine.defaultsKey)

        XCTAssertEqual(ModelRouteCatalog.currentASRId(defaults: defaults), "cloud-qwen-asr-flash-realtime")
    }

    func testCurrentASRIdDefaultsToQwenRealtimeWhenUnset() {
        let defaults = freshDefaults("asr-unset")

        XCTAssertEqual(ModelRouteCatalog.currentASRId(defaults: defaults), "cloud-qwen-asr-flash-realtime")
    }

    // MARK: - currentLLMId

    func testCurrentLLMIdCloudProvider() {
        let defaults = freshDefaults("llm-cloud")
        defaults.set("openai", forKey: "byok.llm.provider")

        XCTAssertEqual(ModelRouteCatalog.currentLLMId(defaults: defaults), "openai")
    }

    func testCurrentLLMIdFallsBackToFirstPresetWhenUnknown() {
        let defaults = freshDefaults("llm-fallback")
        defaults.set("", forKey: "byok.llm.provider")

        let result = ModelRouteCatalog.currentLLMId(defaults: defaults)
        XCTAssertNotEqual(result, "offline")
        // The fallback (qwen) is multi-plan, so the id is plan-tagged (qwen#payg) — match the base.
        let base = ModelRouteOptionID.parse(result).base
        XCTAssertTrue(ProviderCatalog.presets(for: .llm).contains { $0.id == base })
    }

    func testCurrentTTSIdReflectsStoredEngine() {
        let defaults = freshDefaults("tts-current")
        defaults.set("cloud-minimax", forKey: TTSEngine.defaultsKey)

        XCTAssertEqual(ModelRouteCatalog.currentTTSId(defaults: defaults), "cloud-minimax")
    }

    // MARK: - Option lists

    func testASROptionsExpandMultiPlanProviderPerPlan() {
        let ids = ModelRouteCatalog.asrOptions.map(\.id)
        // MiMo ASR is multi-plan → two plan-tagged entries (no bare entry); others stay 1:1.
        XCTAssertTrue(ids.contains("cloud-mimo#payg"))
        XCTAssertTrue(ids.contains("cloud-mimo#package"))
        XCTAssertFalse(ids.contains("cloud-mimo"))
        XCTAssertTrue(ids.contains("apple"))
        XCTAssertTrue(ids.contains("cloud-qwen-asr-flash-realtime"))
        XCTAssertTrue(ids.contains("cloud-volcengine-realtime"))
        XCTAssertFalse(ids.contains("cloud-fun-asr-whole"))
        XCTAssertFalse(ids.contains("cloud-fun-asr"))
        XCTAssertFalse(ids.contains("cloud-zhipu"))
        // Retired Aliyun routes are deleted; only the pinned Qwen realtime route remains.
        XCTAssertFalse(ids.contains("cloud-qwen-asr-flash"))
        XCTAssertFalse(ids.contains("cloud-volcengine-flash"))
    }

    func testLLMOptionsExpandMultiPlanProviderPerPlan() {
        let ids = ModelRouteCatalog.llmOptions.map(\.id)
        XCTAssertTrue(ids.contains("mimo#payg"))
        XCTAssertTrue(ids.contains("mimo#package"))
        XCTAssertTrue(ids.contains("qwen#payg"))
        XCTAssertTrue(ids.contains("qwen#package"))
        XCTAssertTrue(ids.contains("doubao"))
        XCTAssertTrue(ids.contains("deepseek"))   // single-plan provider stays bare
        // The offline/Ollama LLM lane was removed — llmOptions now derives purely from cloud presets.
        XCTAssertFalse(ids.contains("offline"))
    }

    func testTTSOptionsIncludeCloudAndLocalEngines() {
        let ids = ModelRouteCatalog.ttsOptions.map(\.id)
        XCTAssertTrue(ids.contains("cloud-volcengine-tts"))
        XCTAssertTrue(ids.contains("cloud-minimax"))
        XCTAssertTrue(ids.contains("local-kokoro"))
    }

    private func freshDefaults(_ suffix: String) -> UserDefaults {
        let name = "ModelRouteCatalogTests.\(suffix)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
