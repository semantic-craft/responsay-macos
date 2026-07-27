import Testing
import Foundation
@testable import ResponsayCore

// 豆包搜索 Global 版的 Query 硬上限是 100 字符,而语音提问动辄几百字。超限才提炼
// (省一次往返),没超原样送;模型输出还要清洗——它很爱加引号、加「检索词:」前缀。

@Suite struct SearchQueryDistillerTests {

    @Test func needsDistilling_onlyAboveTheLimit() {
        #expect(SearchQueryDistiller.needsDistilling(String(repeating: "字", count: 101), limit: 100))
        #expect(!SearchQueryDistiller.needsDistilling(String(repeating: "字", count: 100), limit: 100))
        #expect(!SearchQueryDistiller.needsDistilling("  短问题  ", limit: 100))
    }

    @Test func clean_stripsQuotesPrefixesAndExtraLines() {
        #expect(SearchQueryDistiller.clean("“北京 天安门 开放时间”", limit: 100) == "北京 天安门 开放时间")
        #expect(SearchQueryDistiller.clean("检索词：民法典 第一千零七十九条", limit: 100) == "民法典 第一千零七十九条")
        #expect(SearchQueryDistiller.clean("民法典 离婚冷静期\n（说明：这是检索词）", limit: 100) == "民法典 离婚冷静期")
    }

    @Test func clean_collapsesWhitespaceAndTruncates() {
        #expect(SearchQueryDistiller.clean("a    b\tc", limit: 100) == "a b c")
        #expect(SearchQueryDistiller.clean(String(repeating: "字", count: 300), limit: 100)?.count == 100)
    }

    @Test func clean_isNilWhenModelReturnedNothingUsable() {
        #expect(SearchQueryDistiller.clean("", limit: 100) == nil)
        #expect(SearchQueryDistiller.clean("   \n  ", limit: 100) == nil)
        #expect(SearchQueryDistiller.clean("\"\"", limit: 100) == nil)
    }

    /// 提炼失败的兜底:截断。搜个糙检索词,好过整条联网路径失败、退回纯记忆作答。
    @Test func truncated_capsAtLimit() {
        #expect(SearchQueryDistiller.truncated(String(repeating: "字", count: 300), limit: 100).count == 100)
        #expect(SearchQueryDistiller.truncated("  短  ", limit: 100) == "短")
    }
}
