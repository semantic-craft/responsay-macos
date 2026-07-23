import Testing
@testable import ResponsayCore

/// 中文规范排版引擎单测：逐条确定性规则 + 指纹护栏 + 编排回退。
/// 规则移植自法墨，标点宽度复用法言 `OCRTextCleanupAction`——此处验证组合后的行为。
struct ChineseTypesettingTests {

    // MARK: 省略号 / 破折号

    @Test func ellipsisAndDash() {
        #expect(ChineseTypesetting.normalizeEllipsisAndDash("等等...") == "等等……")
        #expect(ChineseTypesetting.normalizeEllipsisAndDash("等等。。。") == "等等……")
        #expect(ChineseTypesetting.normalizeEllipsisAndDash("范围--另见") == "范围——另见")
        // 单个 ASCII 连字符不动（连字符 / 区间）
        #expect(ChineseTypesetting.normalizeEllipsisAndDash("co-op") == "co-op")
    }

    // MARK: 引号

    @Test func quotes() {
        #expect(ChineseTypesetting.normalizeQuotes("他说\"你好\"") == "他说“你好”")
        #expect(ChineseTypesetting.normalizeQuotes("「书名」") == "“书名”")
        #expect(ChineseTypesetting.normalizeQuotes("『甲』") == "‘甲’")
        // 英文所有格 / 缩写里的撇号保留
        #expect(ChineseTypesetting.normalizeQuotes("don't") == "don't")
        // 汉字之间的直单引号要转弯引号
        #expect(ChineseTypesetting.normalizeQuotes("'乙'") == "‘乙’")
    }

    // MARK: 全角括号（法言引擎不含，本引擎补）

    @Test func brackets() {
        // 紧挨 CJK → 全角
        #expect(ChineseTypesetting.normalizeBrackets("附注(甲)如下") == "附注（甲）如下")
        // 数字 / 英文语境保持半角
        #expect(ChineseTypesetting.normalizeBrackets("第(2022)号") == "第(2022)号")
        #expect(ChineseTypesetting.normalizeBrackets("func(x)") == "func(x)")
    }

    // MARK: 盘古之白（空格规范化）

    @Test func spacing() {
        // CJK↔拉丁：插一个空格
        #expect(ChineseTypesetting.normalizeSpaces("中文abc测试") == "中文 abc 测试")
        // CJK↔CJK：删空格
        #expect(ChineseTypesetting.normalizeSpaces("你 好") == "你好")
        // CJK↔数字：不留空
        #expect(ChineseTypesetting.normalizeSpaces("第 3 条") == "第3条")
        // 已有一个空格保持恰好一个
        #expect(ChineseTypesetting.normalizeSpaces("文本 abc") == "文本 abc")
    }

    // MARK: 半→全角标点（复用法言引擎，验证组合可用）

    @Test func punctuationWidthReusesLegalEngine() {
        #expect(ChineseTypesetting.finalize("中文,测试.") == "中文，测试。")
    }

    // MARK: 指纹护栏不变式

    @Test func finalizePreservesContentFingerprint() {
        let samples = [
            "他说\"你好\"...太好了",
            "看图(甲)与func(x)",
            "第 3 条 规定 abc123",
            "'引'用「书名」，见 http://a.com/b",
        ]
        for s in samples {
            #expect(
                ChineseTypesetting.contentFingerprint(ChineseTypesetting.finalize(s))
                    == ChineseTypesetting.contentFingerprint(s),
                "finalize 改动了文字：\(s)"
            )
        }
    }

    @Test func contentFingerprintIgnoresPunctuationAndSpace() {
        #expect(
            ChineseTypesetting.contentFingerprint("“中文”, abc")
                == ChineseTypesetting.contentFingerprint("\"中文\"，abc")
        )
    }

    // MARK: 编排（指纹护栏择一 + finalize）

    @Test func assembleKeepsContentPreservingReflow() {
        // AI 只把断行拼成段落、没动文字（指纹一致）→ 采用重排结果
        let out = ChineseTypesetting.assemble(cleaned: "第一行\n第二行\n\n第二段", reflowed: "第一行第二行\n\n第二段")
        #expect(out.contains("第一行第二行"))
    }

    @Test func assembleDiscardsReflowThatAltersContent() {
        // AI 擅自加字（或选区夹带 injection 被照做）→ 指纹不符 → 丢弃，回退纯规则
        let out = ChineseTypesetting.assemble(cleaned: "重要条款", reflowed: "重要条款（我加的解释）")
        #expect(out == "重要条款")
    }

    @Test func assembleFallsBackWhenNoReflow() {
        // 无 AI / 调用失败（reflowed = nil）→ 纯规则整理，仍可用
        let out = ChineseTypesetting.assemble(cleaned: "文本 abc", reflowed: nil)
        #expect(out == "文本 abc")
    }
}
