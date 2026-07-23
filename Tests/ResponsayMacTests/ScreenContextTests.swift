import Testing
@testable import ResponsayMac
@testable import ResponsayCore

/// 屏幕上下文 pure-logic coverage. The AX tree walk itself needs a real Mac + Accessibility grant
/// (HITL), so these pin the deterministic pieces: text joining, the 任意提问 context block, and the
/// per-field cap.
struct ScreenContextTests {

    // MARK: - VisibleTextCollector.smartJoin

    @Test func smartJoinSeparatesBodyRunsWithSpacesAndChromeWithNewlines() {
        let joined = VisibleTextCollector.smartJoin([
            ("Pull Request", false),   // a link/button label
            ("This fixes", true),      // body
            ("the leak", true),        // body — joins with a space
            ("Write a comment", false), // chrome again — newline
        ])
        #expect(joined == "Pull Request\nThis fixes the leak\nWrite a comment")
    }

    @Test func smartJoinEmptyIsEmptyString() {
        #expect(VisibleTextCollector.smartJoin([]).isEmpty)
    }

    // MARK: - askContextBlock (任意提问)

    @Test func askContextBlockLeadsWithScreenAndWrapsWhenPresent() {
        let context = ExpressionContext(
            appName: "Google Chrome", windowTitle: "PR #3421",
            selectedText: "TTL approach", visibleScreenText: "Conversation Commits Checks")
        let block = ExpressPromptBuilder.askContextBlock(context)
        #expect(block != nil)
        #expect(block!.hasPrefix("[屏幕上下文]"))
        #expect(block!.hasSuffix("[屏幕上下文结束]"))
        #expect(block!.contains("Google Chrome"))
        #expect(block!.contains("Conversation Commits Checks"))
    }

    @Test func askContextBlockNilWhenNoScreenSignal() {
        #expect(ExpressPromptBuilder.askContextBlock(nil) == nil)
        #expect(ExpressPromptBuilder.askContextBlock(ExpressionContext(hotwords: ["foo"])) == nil)
    }

    // MARK: - transformContextBlock (整理/翻译/改写)

    @Test func transformContextBlockIncludesAppCursorAndScreenButNotSelection() {
        let context = ExpressionContext(
            appName: "Notes", windowTitle: "会议纪要",
            selectedText: "这段是输入本身",
            textBeforeCursor: "前文", textAfterCursor: "后文",
            visibleScreenText: "整屏内容")
        let block = ExpressPromptBuilder.transformContextBlock(context)
        #expect(block != nil)
        #expect(block!.contains("Notes"))
        #expect(block!.contains("前文"))
        #expect(block!.contains("整屏内容"))
        // selectedText IS the input for 改写/翻译 — must not be duplicated into the context block.
        #expect(!block!.contains("这段是输入本身"))
    }

    @Test func transformContextBlockNilWhenNoUsefulSignal() {
        #expect(ExpressPromptBuilder.transformContextBlock(nil) == nil)
        // only selectedText (the input) → no context block
        #expect(ExpressPromptBuilder.transformContextBlock(
            ExpressionContext(selectedText: "x")) == nil)
        // 515: hotwords alone ARE a useful signal now — the dictionary line is the block
        // (pre-515 they were dropped here and the block was nil).
        #expect(ExpressPromptBuilder.transformContextBlock(
            ExpressionContext(selectedText: "x", hotwords: ["y"])) == "用户词典/专有名词：y")
    }

    // MARK: - ExpressionContext cap

    @Test func visibleScreenTextCappedAt2000() {
        let long = String(repeating: "字", count: 5000)
        let context = ExpressionContext().withVisibleScreenText(long)
        #expect(context.visibleScreenText?.count == 2000)
    }
}
