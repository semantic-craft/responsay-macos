import XCTest
@testable import ResponsayMac
import ResponsayCore

/// 截图翻译 译文服务 list: only keyed LLM providers show, the current provider is the default,
/// and nothing configured yields an empty list / nil default. Dispatcher key reads are stubbed,
/// so this runs without the real Keychain.
final class SnapTranslateServiceCatalogTests: XCTestCase {

    private func defaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "snap-translate-catalog-\(UUID().uuidString)")!
        return d
    }

    /// keyReader that returns a key for every account → every cloud provider is "configured".
    private let allKeyed: (String) -> String? = { _ in "sk-test" }
    /// keyReader that returns no keys → nothing configured.
    private let noKeys: (String) -> String? = { _ in nil }

    func testServices_withKeysForAll_listsCloudLLMProviders() {
        let dispatcher = ProviderConfigDispatcher(defaults: defaults(), keyReader: allKeyed)
        let services = SnapTranslateServiceCatalog.services(dispatcher: dispatcher)

        XCTAssertFalse(services.isEmpty)
        // A well-known cloud LLM provider is present; the local engine never is (no key).
        XCTAssertTrue(services.contains { $0.id == "qwen" })
        XCTAssertFalse(services.contains { $0.id == "apple" })
        // Order matches the LLM picker's catalog order.
        XCTAssertEqual(services.map(\.id), ProviderCatalog.presets(for: .llm).map(\.id).filter { $0 != "apple" })
    }

    func testServices_withNoKeys_isEmpty() {
        let dispatcher = ProviderConfigDispatcher(defaults: defaults(), keyReader: noKeys)
        XCTAssertTrue(SnapTranslateServiceCatalog.services(dispatcher: dispatcher).isEmpty)
    }

    func testDefaultServiceId_honoursCurrentProvider_whenKeyed() {
        let d = defaults()
        d.set("gemini", forKey: "byok.llm.provider")
        let dispatcher = ProviderConfigDispatcher(defaults: d, keyReader: allKeyed)

        XCTAssertEqual(SnapTranslateServiceCatalog.defaultServiceId(defaults: d, dispatcher: dispatcher), "gemini")
    }

    func testDefaultServiceId_fallsBackToFirstKeyed_whenNoneSelected() {
        let d = defaults()
        let dispatcher = ProviderConfigDispatcher(defaults: d, keyReader: allKeyed)
        let first = SnapTranslateServiceCatalog.services(dispatcher: dispatcher).first?.id

        XCTAssertEqual(SnapTranslateServiceCatalog.defaultServiceId(defaults: d, dispatcher: dispatcher), first)
        XCTAssertNotNil(first)
    }

    func testDefaultServiceId_isNil_whenNothingConfigured() {
        let d = defaults()
        let dispatcher = ProviderConfigDispatcher(defaults: d, keyReader: noKeys)
        XCTAssertNil(SnapTranslateServiceCatalog.defaultServiceId(defaults: d, dispatcher: dispatcher))
    }
}
