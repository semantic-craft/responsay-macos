import Testing
import Foundation
@testable import ResponsayCore

// 搜索引擎兜底（215 扩展）：学术文献/译著在知网、百度学术查不到时（如新出译著尚未被
// 学术库收录），再给一条通用搜索引擎（百度网页）深链，直达出版社/书目页核验真伪。
@Suite("搜索引擎兜底（scholarlyArticle）")
struct WebSearchFallbackTests {
    let gen = SearchStrategyGenerator()
    let router = VerificationQueryRouter()

    private func scholar(_ q: String) -> VerificationAnchor {
        VerificationAnchor(id: "s:\(q)", label: q, kind: .scholarlyArticle, status: .pending, query: q)
    }

    @Test("学术文献策略 = 知网 + 百度学术 + 搜索引擎兜底（兜底排最后）")
    func scholarlyIncludesFallback() {
        let s = gen.strategy(for: scholar("张贤伟 法律是可计算的吗"), scene: .academicWriting)
        #expect(s.routes.map { $0.source } == [.cnki, .baiduScholar, .webSearch])
    }

    @Test("搜索引擎兜底路由 → 百度网页搜索深链（非付费学术库）")
    func fallbackRouteIsBaiduWeb() {
        let route = router.route(for: scholar("张贤伟 法律是可计算的吗"), source: .webSearch)
        #expect(route.kind == .deepLink)
        let url = route.url?.absoluteString ?? ""
        #expect(url.contains("www.baidu.com/s"))
        #expect(url.contains("wd="))
    }

    @Test("法条仍只走国家法规库/法宝，不掺搜索引擎兜底")
    func lawHasNoFallback() {
        let a = VerificationAnchor(id: "l", label: "《民法典》第577条", kind: .law,
                                   status: .pending, query: "民法典 577")
        let s = gen.strategy(for: a, scene: .litigation)
        #expect(!s.routes.map { $0.source }.contains(.webSearch))
    }
}
