import XCTest
import ResponsayCore
@testable import ResponsayMac

/// Epic 238 — `LLMEndpointResolver` bridges the BYOK LLM card to the App-direct path.
/// `resolveText` (rewrite/translate/express/legal) and `resolveCloud` both resolve the BYOK
/// cloud card. Pure given injected defaults + dispatcher.
final class LLMEndpointResolverTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "test.llmEndpointResolver"

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

    func test_resolveCloud_unconfigured_returnsNil() {
        XCTAssertNil(LLMEndpointResolver.resolveCloud(defaults: defaults, dispatcher: dispatcher()))
    }

    func test_resolveCloud_configured_returnsCloudEndpoint() {
        let endpoint = LLMEndpointResolver.resolveCloud(
            defaults: defaults, dispatcher: dispatcher(keys: ["byok.qwen": "sk-1"]))
        XCTAssertEqual(endpoint?.providerId, "qwen")
        XCTAssertEqual(endpoint?.apiKey, "sk-1")
        XCTAssertFalse(endpoint?.isLocal ?? true)
    }

    func test_resolveCloud_forcesThinkingOff() {
        let endpoint = LLMEndpointResolver.resolveCloud(
            defaults: defaults, dispatcher: dispatcher(keys: ["byok.qwen": "sk-1"]))
        XCTAssertEqual(endpoint?.thinkingEnabled, false)
    }
}
