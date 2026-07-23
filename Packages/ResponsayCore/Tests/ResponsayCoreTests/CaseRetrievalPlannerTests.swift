import Testing
import Foundation
@testable import ResponsayCore

/// 474 — 类案检索渠道表（PRD S2）：把案情字段填进分层渠道模板，产出"可执行检索作战图"（每条 = 检索式 +
/// 直达 URL）。思路取自文章（P0–P3 + 案号精搜 + filetype:pdf），源用我们可信法律站；复用 router 的 URL 构造。
@Suite struct CaseRetrievalPlannerTests {
    @Test func caseNumberExactSearchProducesQuotedQueryAndURL() throws {
        let plans = CaseRetrievalPlanner.plan(CaseFacts(caseNumber: "（2024）皖1702刑初229号"))
        let p0 = try #require(plans.first { $0.channel.tier == 0 })
        #expect(p0.query.contains("\"（2024）皖1702刑初229号\""))   // 引号精确
        #expect(p0.url?.absoluteString.contains("bing.com/search") == true)
    }

    @Test func includesCredibleLegalSourcesAndGatesOnFields() {
        let facts = CaseFacts(causeOfAction: "买卖合同纠纷", year: "2024",
                              keywords: "免责条款 效力", charge: "诈骗")
        let plans = CaseRetrievalPlanner.plan(facts)
        let ids = plans.map(\.channel.id)
        #expect(ids.contains("E1-P1-055"))   // 律师平台 055110
        #expect(ids.contains("E1-P1-rmfy"))  // 人民法院案例库
        #expect(ids.contains("E3-P1-spc"))   // 最高法指导性案例（site:court.gov.cn）
        #expect(ids.contains("E4-P1-spp"))   // 最高检典型案例（site:spp.gov.cn）
        #expect(plans.contains { $0.query.contains("site:spp.gov.cn") })  // 两高官方源直达
        #expect(ids.contains("E1-P2-fx"))    // 法信
        #expect(ids.contains("E1-P2-cc"))    // 中国法院网法律文库
        #expect(ids.contains("E1-P2-wb"))    // 湾区律师网
        #expect(!ids.contains("E1-P0-cn"))   // 无案号 → 案号精搜跳过
        #expect(plans.map(\.channel.tier) == plans.map(\.channel.tier).sorted())  // tier 升序
        #expect(plans.contains { $0.query.contains("filetype:pdf") })             // PDF 打法
        #expect(plans.contains { $0.query.contains("site:055110.com") })          // site: 形态
    }
}

@Suite struct CaseNumberCrossCheckTests {
    @Test func buildsQuotedQueriesIncludingNewsSources() {
        let qs = CaseNumberCrossCheck.queries(for: "（2024）皖1702刑初229号")
        #expect(qs.allSatisfy { $0.contains("\"（2024）皖1702刑初229号\"") })   // 全部引号精确
        #expect(qs.contains { $0.contains("news.qq.com") })                    // 新闻源做交叉确认
    }

    @Test func independentSourcesDedupeByHost() {
        let urls = ["https://wenshu.court.gov.cn/a", "https://wenshu.court.gov.cn/b", "https://news.qq.com/x"]
        #expect(CaseNumberCrossCheck.independentSources(matchedURLs: urls) == 2)  // 同域算一个独立来源
    }

    @Test func oneIndependentSourceVerifiesElsePending() {
        #expect(CaseNumberCrossCheck.classify(independentSources: 1) == .verified)
        #expect(CaseNumberCrossCheck.classify(independentSources: 0) == .pending)
    }
}

@Suite struct TypicalCaseQuotaTests {
    @Test func capsTypicalShareAtThirtyPercent() {
        #expect(TypicalCaseQuota.allowedTypicalCount(regularCount: 7) == 3)    // 3/10 = 30%
        #expect(TypicalCaseQuota.allowedTypicalCount(regularCount: 10) == 4)   // 4/14 ≈ 28.6%
        #expect(TypicalCaseQuota.allowedTypicalCount(regularCount: 0) == 0)    // 不能全靠两高
    }

    @Test func enforceKeepsAllRegularAndCapsTypical() {
        let kept = TypicalCaseQuota.enforce(
            regular: ["a", "b", "c", "d", "e", "f", "g"], typical: ["T1", "T2", "T3", "T4", "T5"])
        #expect(kept.count == 10)                                  // 7 普通 + 3 两高
        #expect(kept.filter { $0.hasPrefix("T") }.count == 3)
    }
}
