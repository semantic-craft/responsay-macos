import XCTest
import ResponsayCore
@testable import ResponsayMac

/// 435 — the resolver wiring of `LLMThinkingPolicy`: text REWRITE is always thinking-off
/// regardless of the global 思考 toggle; open CHAT (voice assistant / 任意提问) honors it.
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

    func testRewriteForcesThinkingOffEvenWhenGlobalToggleOn() {
        defaults.set(true, forKey: LLMEndpointResolver.thinkingKey)
        let endpoint = LLMEndpointResolver.resolveText(defaults: defaults, dispatcher: configuredDispatcher)
        XCTAssertEqual(endpoint?.thinkingEnabled, false)
    }

    func testChatHonorsGlobalToggleOn() {
        defaults.set(true, forKey: LLMEndpointResolver.thinkingKey)
        let endpoint = LLMEndpointResolver.resolveChat(defaults: defaults, dispatcher: configuredDispatcher)
        XCTAssertEqual(endpoint?.thinkingEnabled, true)
    }

    func testChatHonorsGlobalToggleOff() {
        defaults.set(false, forKey: LLMEndpointResolver.thinkingKey)
        let endpoint = LLMEndpointResolver.resolveChat(defaults: defaults, dispatcher: configuredDispatcher)
        XCTAssertEqual(endpoint?.thinkingEnabled, false)
    }

    func testRewriteStaysOffWhenToggleOff() {
        defaults.set(false, forKey: LLMEndpointResolver.thinkingKey)
        let endpoint = LLMEndpointResolver.resolveText(defaults: defaults, dispatcher: configuredDispatcher)
        XCTAssertEqual(endpoint?.thinkingEnabled, false)
    }
}
