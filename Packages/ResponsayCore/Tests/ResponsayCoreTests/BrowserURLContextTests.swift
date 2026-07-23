import Testing
import Foundation
@testable import ResponsayCore

/// 508 — the full browser URL reaches the LLM: it lands in the cloud `jsonObject`
/// payload and in every prompt-context block, replacing the host-only routing signal.
/// T1 headless (pure value type + prompt assembly — no AX, no network).
struct BrowserURLContextTests {
    private let url = "https://www.court.gov.cn/case/2024-final-judgment?id=123"

    @Test func jsonObjectIncludesFullURL() {
        let ctx = ExpressionContext(browserURL: url)
        #expect(ctx.jsonObject["browserURL"] as? String == url)   // full URL, not the host
    }

    @Test func jsonObjectOmitsURLWhenAbsent() {
        #expect(ExpressionContext(appName: "TextEdit").jsonObject["browserURL"] == nil)
    }

    @Test func urlIsCappedAt300() {
        let long = "https://x.com/" + String(repeating: "a", count: 500)
        let value = ExpressionContext(browserURL: long).jsonObject["browserURL"] as? String
        #expect(value?.count == 300)
    }

    @Test func withBrowserURLStoresFullURLNotHost() {
        let value = ExpressionContext().withBrowserURL(url).jsonObject["browserURL"] as? String
        #expect(value == url)   // not reduced to "www.court.gov.cn"
    }

    @Test func contextLinesIncludeURL() {
        let lines = ExpressPromptBuilder.contextLines(ExpressionContext(browserURL: url))
        #expect(lines.contains { $0.contains(url) })
    }

    @Test func transformContextBlockIncludesURL() {
        let block = ExpressPromptBuilder.transformContextBlock(ExpressionContext(browserURL: url))
        #expect(block?.contains(url) == true)
    }

    @Test func askContextBlockIncludesURL() {
        let block = ExpressPromptBuilder.askContextBlock(ExpressionContext(browserURL: url))
        #expect(block?.contains(url) == true)
    }

    @Test func absentURLLeavesBlocksUnchanged() {
        #expect(ExpressPromptBuilder.transformContextBlock(ExpressionContext()) == nil)
        #expect(ExpressPromptBuilder.contextLines(ExpressionContext()).isEmpty)
    }
}
