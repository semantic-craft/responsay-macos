import Testing
@testable import ResponsayCore

/// 517 — 屏幕专名采集（当次临时偏置的纯提取端）。Screen text in → candidate proper-noun terms
/// out; never persisted, never into the dictionary. v1 is ASCII-only (用户痛点=英文专名);
/// CJK 专名是升级路。
struct ScreenTermHarvesterTests {
    @Test func extractsTheThreeShapesInClassOrder() {
        // 大写词组 > 驼峰/内部大写 > 数字/连字符 —— 词组是最强的人名/品牌信号，cap 时先活。
        let text = """
        Skills by Matt Pocock are listed here
        upgrade to Qwen3-ASR and DeepSeek today
        Typeless is fast. Typeless is quiet.
        """
        #expect(ScreenTermHarvester.harvest(text)
            == ["Matt Pocock", "Qwen3-ASR", "DeepSeek", "Typeless"])
    }

    @Test func ordinarySentenceYieldsNothing() {
        // 句首大写普通词（The/We）因存在小写形式被滤掉；一次性大写单词（freq<2）也不收。
        let text = "The quick brown fox jumps over the lazy dog. We think the fox is fine, we do. Remotion powers it."
        #expect(ScreenTermHarvester.harvest(text).isEmpty)
    }

    @Test func allCapsUIChromeAndPureDigitsAreIgnored() {
        #expect(ScreenTermHarvester.harvest("FILE EDIT VIEW HELP 2026 1.3.32 OK").isEmpty)
    }

    @Test func dictionaryTermsAreExcludedCaseInsensitively() {
        let terms = ScreenTermHarvester.harvest(
            "Matt Pocock teaches TypeScript",
            excluding: ["matt pocock"])
        #expect(terms == ["TypeScript"])
    }

    @Test func phraseComponentsAreNotReEmittedAsSingles() {
        // "Matt" 出现两次且无小写形式，但已被词组覆盖 → 不再单独出词。
        let terms = ScreenTermHarvester.harvest("Matt Pocock and Matt are here. Matt Pocock again.")
        #expect(terms == ["Matt Pocock"])
    }

    @Test func capsAtTwelveTerms() {
        let text = (1...15).map { "Tool\($0)-x" }.joined(separator: "\n")
        let terms = ScreenTermHarvester.harvest(text)
        #expect(terms.count == 12)
        #expect(terms.first == "Tool1-x")
        #expect(!terms.contains("Tool13-x"))
    }

    @Test func overlongAndTitleCaseHeadingsAreDropped() {
        // >80 字符的 token 是垃圾；>4 词的连续大写词组是 Title Case 标题/菜单 chrome。
        let long = "Ab" + String(repeating: "c", count: 90)
        let text = "\(long) here\nGetting Started With Swift Testing Guide"
        #expect(ScreenTermHarvester.harvest(text).isEmpty)
    }

    @Test func cjkTextOnlyYieldsASCIITerms() {
        #expect(ScreenTermHarvester.harvest("深度求索发布了 DeepSeek 模型") == ["DeepSeek"])
    }
}
