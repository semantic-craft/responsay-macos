import XCTest
import ResponsayCore
@testable import ResponsayMac

final class ModelRouteSelectionSectionTests: XCTestCase {
    func testLLMSelectionResetsModelWhenSwitchingProviderFromStaleMimo() {
        let defaults = freshDefaults("mimo-to-deepseek")
        defaults.set("mimo", forKey: "byok.llm.provider")
        defaults.set("mimo-v2.5-pro", forKey: "byok.llm.mimo.model")
        defaults.set(
            "https://token-plan-cn.xiaomimimo.com/v1",
            forKey: "byok.llm.mimo.baseURL")

        ModelRouteSelectionActions.applyLLMSelection("deepseek", defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: "byok.llm.provider"), "deepseek")
        XCTAssertEqual(defaults.string(forKey: "byok.llm.deepseek.model"), "deepseek-v4-flash")
        XCTAssertEqual(
            defaults.string(forKey: "byok.llm.deepseek.baseURL"),
            "https://api.deepseek.com/v1")
    }

    func testLLMSelectionResetsModelWhenSwitchingProviderFromStaleDoubao() {
        let defaults = freshDefaults("doubao-to-mimo")
        defaults.set("doubao", forKey: "byok.llm.provider")
        defaults.set("doubao-seed-1-6", forKey: "byok.llm.doubao.model")
        defaults.set(
            "https://ark.cn-beijing.volces.com/api/v3",
            forKey: "byok.llm.doubao.baseURL")

        ModelRouteSelectionActions.applyLLMSelection("mimo", defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: "byok.llm.provider"), "mimo")
        XCTAssertEqual(defaults.string(forKey: "byok.llm.mimo.model"), "mimo-v2.5")
        XCTAssertEqual(
            defaults.string(forKey: "byok.llm.mimo.baseURL"),
            "https://token-plan-cn.xiaomimimo.com/v1")
    }

    // Picking a plan-tagged model option switches the billing plan in-place: same provider,
    // but plan + Base URL follow, so the next call hits the right host.
    func testLLMSelectionWithPlanTagSwitchesPlanAndEndpoint() {
        let defaults = freshDefaults("mimo-plan-switch")

        ModelRouteSelectionActions.applyLLMSelection("mimo#payg", defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: "byok.llm.provider"), "mimo")
        XCTAssertEqual(defaults.string(forKey: "byok.llm.mimo.plan"), BillingPlan.payg.rawValue)
        XCTAssertEqual(
            defaults.string(forKey: "byok.llm.mimo.baseURL"),
            "https://api.xiaomimimo.com/v1")

        ModelRouteSelectionActions.applyLLMSelection("mimo#package", defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: "byok.llm.provider"), "mimo")
        XCTAssertEqual(defaults.string(forKey: "byok.llm.mimo.plan"), BillingPlan.package.rawValue)
        XCTAssertEqual(
            defaults.string(forKey: "byok.llm.mimo.baseURL"),
            "https://token-plan-cn.xiaomimimo.com/v1")
    }

    func testPickerIncludesDoubaoLLMButKeepsRetiredVolcengineRoutesOut() {
        XCTAssertTrue(ProviderCatalog.presets(for: .llm).contains { $0.id == "doubao" })
        XCTAssertFalse(ProviderCatalog.presets(for: .tts).contains { $0.id == "doubao" })
        XCTAssertFalse(ProviderCatalog.presets(for: .asr).contains { $0.id == "volc-asr" })
        XCTAssertTrue(ProviderCatalog.presets(for: .asr).contains { $0.id == "volcengine-flash" })
    }

    private func freshDefaults(_ suffix: String) -> UserDefaults {
        let name = "ModelRouteSelectionSectionTests.\(suffix)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
