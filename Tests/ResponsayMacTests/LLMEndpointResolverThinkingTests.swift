import XCTest
import ResponsayCore
@testable import ResponsayMac

/// 思考 is forced off on every resolver path — there is no user toggle, and a stale
/// `byok.llm.thinking` left in UserDefaults by an older build must not turn it back on.
/// Pure given an injected dispatcher + defaults (no Keychain, no app launch).
final class LLMEndpointResolverThinkingTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "test.llmEndpointResolverThinking"

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

    /// A configured cloud LLM (default qwen preset + any non-empty key) so the resolver
    /// returns a non-nil endpoint whose `thinkingEnabled` we can inspect.
    private var configuredDispatcher: ProviderConfigDispatcher {
        ProviderConfigDispatcher(defaults: defaults, keyReader: { _ in "sk-test" })
    }

    func testRewriteIsThinkingOff() {
        let endpoint = LLMEndpointResolver.resolveText(defaults: defaults, dispatcher: configuredDispatcher)
        XCTAssertEqual(endpoint?.thinkingEnabled, false)
    }

    func testChatIsThinkingOff() {
        let endpoint = LLMEndpointResolver.resolveChat(defaults: defaults, dispatcher: configuredDispatcher)
        XCTAssertEqual(endpoint?.thinkingEnabled, false)
    }

    func testSearchIsThinkingOff() {
        let endpoint = LLMEndpointResolver.resolveSearch(defaults: defaults, dispatcher: configuredDispatcher)
        XCTAssertEqual(endpoint?.thinkingEnabled, false)
    }

    /// A legacy on-toggle in UserDefaults is ignored — the key is no longer read at all.
    func testStaleLegacyToggleIsIgnored() {
        defaults.set(true, forKey: "byok.llm.thinking")
        XCTAssertEqual(
            LLMEndpointResolver.resolveChat(defaults: defaults, dispatcher: configuredDispatcher)?.thinkingEnabled,
            false)
        XCTAssertEqual(
            LLMEndpointResolver.resolveText(defaults: defaults, dispatcher: configuredDispatcher)?.thinkingEnabled,
            false)
    }
}
