import Testing
@testable import ResponsayCore

// 纠正胶囊「点名可疑词」文案 (user 2026-07-06): the chip names the specific mis-heard-looking
// English / proper-noun token instead of a bare「纠正…」, so a first-time user knows what it's for.
// One token →「word」听对了吗？; several →「first」等词听对了吗？; none (the「每次都显示」case on
// plain Chinese) → a generic prompt. The shaped-token rule is the same one the show/hide gate uses.

@Test func chipTitle_singleShapedTerm_namesIt() {
    #expect(MishearCandidates.chipTitle(for: "推荐一个模型叫 DeepSeek") == "「DeepSeek」听对了吗？")
}

@Test func chipTitle_multipleShapedTerms_namesFirstThenDengCi() {
    #expect(MishearCandidates.chipTitle(for: "对比 DeepSeek 和 Kimi 两个模型") == "「DeepSeek」等词听对了吗？")
}

@Test func chipTitle_noShapedTerm_fallsBackToGenericPrompt() {
    // 只有在「每次听写都显示」打开、而这句纯中文时才会走到这里。
    #expect(MishearCandidates.chipTitle(for: "今天天气不错") == "有词听错了？点我纠正")
}

@Test func chipTitle_veryLongTerm_isTruncatedWithEllipsis() {
    // 特别长的词截断，防止胶囊被撑过宽（首 16 字 + …）。
    let title = MishearCandidates.chipTitle(for: "这个词是 Supercalifragilisticexpialidocious")
    #expect(title == "「Supercalifragili…」听对了吗？")
}

@Test func tokens_collectsShapedTermsInFirstSeenOrder_deduped() {
    #expect(MishearCandidates.tokens(in: "先 Kimi 再 DeepSeek 又 DeepSeek") == ["Kimi", "DeepSeek"])
}

@Test func tokens_plainChineseProse_isEmpty() {
    #expect(MishearCandidates.tokens(in: "今天天气不错，我们出去走走吧").isEmpty)
}
