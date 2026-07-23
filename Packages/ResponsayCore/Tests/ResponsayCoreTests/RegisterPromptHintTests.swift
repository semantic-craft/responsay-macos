import Testing
import Foundation
@testable import ResponsayCore

/// 462 — the effective polish styleHint resolver: an explicitly-activated 日常办公 pack OVERRIDES
/// the auto per-app register layer (PRD precedence); otherwise the frontmost app drives a register
/// guidance block. nil → plain tidy (byte-identical to today).
struct RegisterPromptHintTests {
    @Test func chatAppWithoutPackProducesChatRegisterGuidance() {
        let hint = RegisterPromptHint.resolve(
            activePackHint: nil, bundleID: "com.tencent.xinWeChat", appName: "微信")
        let text = try? #require(hint)
        #expect(text?.contains("微信") == true)
        #expect(text?.contains("口语") == true)
    }

    @Test func activePackOverridesPerAppRegister() {
        // PRD §3: an explicitly-activated 日常办公 pack is the user's choice → it wins, verbatim,
        // even when the frontmost app would otherwise classify (here: 微信 → chat).
        let hint = RegisterPromptHint.resolve(
            activePackHint: "用公文体改。", bundleID: "com.tencent.xinWeChat", appName: "微信")
        #expect(hint == "用公文体改。")
    }

    @Test func unknownAppWithoutPackResolvesToNilSoPromptStaysByteIdentical() {
        // Acceptance: 认不出 App / neutral / 无 pack → nil → PolishPromptBuilder appends nothing →
        // the polish prompt is byte-identical to today.
        #expect(RegisterPromptHint.resolve(activePackHint: nil, bundleID: "com.unknown.editor") == nil)
        #expect(RegisterPromptHint.resolve(activePackHint: nil, bundleID: nil, appName: nil) == nil)
    }

    @Test func emptyPackHintFallsThroughToPerAppRegister() {
        // A blank/whitespace pack hint is "no pack" → fall through to the per-app layer, not "" out.
        let hint = RegisterPromptHint.resolve(
            activePackHint: "   ", bundleID: "com.apple.mail", appName: "邮件")
        #expect(hint?.contains("邮件") == true)
    }

    @Test func registerBlockCarriesFloorAndRedLineNotTheCeilingTable() throws {
        let hint = try #require(RegisterPromptHint.resolve(
            activePackHint: nil, bundleID: "com.tencent.xinWeChat", appName: "微信"))
        // floor: this app's own register directive is present.
        #expect(hint.contains("口语"))       // from .chat guidance (this app)
        // freeflow-style conservative red line: register only adjusts tone, never overrides the rules above.
        #expect(hint.contains("以上方为准"))
        // 468 A/B proved the multi-row reference table is inert on the polish path (the faithful-tidy
        // contract dominates) → it was dropped. Other tiers' guidance must NOT leak in.
        #expect(!hint.contains("清晰结构"))   // .document guidance — gone with the table
        #expect(!hint.contains("克制"))       // .legal guidance — gone with the table
    }

    // MARK: - End-to-end through the real PolishPromptBuilder seam

    @Test func neutralHintLeavesPolishPromptByteIdentical() {
        let plain = PolishPromptBuilder.build(text: "你好世界").system
        let withNeutral = PolishPromptBuilder.build(
            text: "你好世界",
            styleHint: RegisterPromptHint.resolve(activePackHint: nil, bundleID: "com.unknown.app")
        ).system
        #expect(withNeutral == plain)
    }

    @Test func knownAppRegisterReachesPromptAfterFaithfulnessFloor() throws {
        let prompt = PolishPromptBuilder.build(
            text: "你好世界",
            styleHint: RegisterPromptHint.resolve(
                activePackHint: nil, bundleID: "com.tencent.xinWeChat", appName: "微信")
        ).system
        let floor = try #require(prompt.range(of: "Faithfulness floor"))
        let register = try #require(prompt.range(of: "按当前应用/场景调整语体"))
        // register block is additive and sits AFTER the faithfulness floor — it never overrides it.
        #expect(floor.lowerBound < register.lowerBound)
    }
}
