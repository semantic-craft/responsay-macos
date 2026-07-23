import Testing
@testable import ResponsayCore

/// 可见文本组装纯逻辑（smartJoin 语义与 macOS/Context/VisibleTextCollector.smartJoin 完全一致：
/// 正文→正文空格连，其余换行）+ 树序砍头（保头保阅读顺序，对齐 Typeless）。
struct VisibleTextComposerTests {
    @Test func smartJoinBodyRunsWithSpacesLabelsOnOwnLines() {
        let joined = VisibleTextComposer.smartJoin([
            ("PR #3421", true), ("fix memory leak", true),
            ("Reviewers", false), ("Labels", false),
        ])
        #expect(joined == "PR #3421 fix memory leak\nReviewers\nLabels")
    }

    @Test func smartJoinLabelThenBodyBreaksLine() {
        let joined = VisibleTextComposer.smartJoin([
            ("发送", false), ("你好", true), ("再见", true),
        ])
        #expect(joined == "发送\n你好 再见")
    }

    @Test func smartJoinEmptyInputYieldsEmptyString() {
        #expect(VisibleTextComposer.smartJoin([]) == "")
    }

    @Test func composeKeepsTreeOrderAndJoins() {
        // 采集（树）顺序原样保留，不做任何几何重排
        let out = VisibleTextComposer.compose([("标题", false), ("正文一", true), ("正文二", true)])
        #expect(out == "标题\n正文一 正文二")
    }

    @Test func composeUnderBudgetReturnsFullJoin() {
        let out = VisibleTextComposer.compose(
            [("上", true), ("中", true), ("下", true)], maxLength: 2000)
        #expect(out == "上 中 下")
    }

    @Test func composeHeadTruncatesKeepsFrontDropsTail() {
        // 超预算 → 保前 maxLength 字符（保头砍尾），末尾内容被丢
        let head = String(repeating: "甲", count: 1500)
        let tail = String(repeating: "乙", count: 1500)
        let out = VisibleTextComposer.compose([(head, true), (tail, true)], maxLength: 2000)
        #expect(out.count == 2000)          // 砍到预算
        #expect(out.hasPrefix(head))        // 头部整块保住
        #expect(out.hasSuffix("乙"))         // 尾部只剩被截断的部分乙
        #expect(!out.contains(tail))        // 完整的尾块没保住（砍尾）
    }

    @Test func composeEmptyInputYieldsEmptyString() {
        #expect(VisibleTextComposer.compose([]) == "")
    }
}
