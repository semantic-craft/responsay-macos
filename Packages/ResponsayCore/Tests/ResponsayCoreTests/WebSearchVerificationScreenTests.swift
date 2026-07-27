import Testing
import Foundation
@testable import ResponsayCore

// 独立检索服务不像模型那样会判断「这条搜到的东西对不对得上」。直接拿第一条回填,
// 会把不相关的网页写成「已核验」——[待核] 机制最不能出的错。这道筛保守到宁可漏判:
// 对不上就返回 nil,锚点保持 pending(搜不到 ≠ 不存在)。

@Suite struct WebSearchVerificationScreenTests {

    private func document(title: String = "", snippet: String = "", url: String = "https://e.com") -> WebSearchDocument {
        WebSearchDocument(title: title, url: url, snippet: snippet)
    }

    /// 案号靠数字定位:三段数字全中,基本不可能是另一个案子。
    @Test func firstMatch_acceptsWhenEveryDigitRunAppears() {
        let matched = WebSearchVerificationScreen.firstMatch(
            documents: [
                document(title: "无关新闻", snippet: "今天天气不错"),
                document(title: "某某与某某合同纠纷案", snippet: "(2021)京01民终1234号 判决书全文"),
            ],
            query: "（2021）京01民终1234号")
        #expect(matched?.snippet.contains("1234") == true)
    }

    /// 法条名这类没有数字锚的引用,靠整串包含命中。
    @Test func firstMatch_acceptsWhenNormalizedQueryIsContained() {
        let matched = WebSearchVerificationScreen.firstMatch(
            documents: [document(title: "民法典第一千零七十九条 —— 离婚", snippet: "条文全文")],
            query: "民法典 第一千零七十九条")
        #expect(matched != nil)
    }

    /// 数字对不齐 = 换了一个案子,必须判不通过。
    @Test func firstMatch_rejectsWhenDigitsDisagree() {
        let matched = WebSearchVerificationScreen.firstMatch(
            documents: [document(title: "另案", snippet: "(2021)京01民终9999号")],
            query: "（2021）京01民终1234号")
        #expect(matched == nil)
    }

    @Test func firstMatch_rejectsUnrelatedResults() {
        let matched = WebSearchVerificationScreen.firstMatch(
            documents: [document(title: "旅游攻略", snippet: "北京周边好去处")],
            query: "民法典第一千零七十九条")
        #expect(matched == nil)
    }

    @Test func firstMatch_rejectsEmptyQuery() {
        #expect(WebSearchVerificationScreen.firstMatch(documents: [document(title: "任意")], query: "  ") == nil)
    }

    /// 全角/半角括号、空格、大小写都不该造成漏判。
    @Test func normalize_dropsPunctuationAndCase() {
        #expect(WebSearchVerificationScreen.normalize("（2021）京 01 民终") == "2021京01民终")
        #expect(WebSearchVerificationScreen.normalize("Smith v. Jones") == "smithvjones")
    }

    @Test func digitRuns_splitsOnNonDigits() {
        #expect(WebSearchVerificationScreen.digitRuns("2021京01民终1234号") == ["2021", "01", "1234"])
        #expect(WebSearchVerificationScreen.digitRuns("民法典").isEmpty)
    }
}
