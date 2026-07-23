import XCTest
@testable import ResponsayCore

/// 435 · Structured text rewrite (express / polish / rewrite / translate) is ALWAYS
/// thinking-off, decoupled from the global 思考 toggle (slow, no benefit). Only open
/// chat (voice assistant / 任意提问) honors the toggle.
final class LLMThinkingPolicyTests: XCTestCase {
    func testRewriteIsAlwaysThinkingOffEvenWhenToggleOn() {
        XCTAssertFalse(LLMThinkingPolicy.thinkingEnabled(purpose: .rewrite, globalToggle: true))
    }

    func testChatHonorsGlobalToggleWhenOn() {
        XCTAssertTrue(LLMThinkingPolicy.thinkingEnabled(purpose: .chat, globalToggle: true))
    }

    func testChatHonorsGlobalToggleWhenOff() {
        XCTAssertFalse(LLMThinkingPolicy.thinkingEnabled(purpose: .chat, globalToggle: false))
    }

    func testRewriteStaysThinkingOffWhenToggleOff() {
        XCTAssertFalse(LLMThinkingPolicy.thinkingEnabled(purpose: .rewrite, globalToggle: false))
    }
}
