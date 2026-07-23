import Testing
import Foundation
@testable import ResponsayCore

/// 166 — VerificationQueryRouter: query generation + per-source route dispatch (seam).
struct VerificationQueryRouterTests {
    private let router = VerificationQueryRouter()

    private func anchor(
        label: String = "《个保法》第24条",
        kind: VerificationKind = .law,
        query: String = "",
        sources: [VerificationSourcePreference] = []
    ) -> VerificationAnchor {
        VerificationAnchor(id: "a", label: label, kind: kind, query: query, preferredSources: sources)
    }

    // MARK: - Query generation

    @Test func query_usesSeededQueryElseLabel() {
        #expect(router.query(for: anchor(query: "个人信息保护法 第24条")) == "个人信息保护法 第24条")
        #expect(router.query(for: anchor(query: "")) == "《个保法》第24条")
    }

    // MARK: - Route dispatch

    @Test func baiduScholar_deepLinksToSearchPage() {
        let route = router.route(for: anchor(kind: .scholarlyArticle, query: "比例原则"), source: .baiduScholar)
        #expect(route.kind == .deepLink)
        #expect(route.url?.host == "xueshu.baidu.com")
        #expect(route.url?.query?.contains("wd=") == true)
    }

    @Test func cnki_deepLinksWithKeywordParam() {
        let route = router.route(for: anchor(), source: .cnki)
        #expect(route.kind == .deepLink)
        #expect(route.url?.host == "kns.cnki.net")
        #expect(route.url?.query?.contains("kw=") == true)
    }

    @Test func govLaw_routesViaBingSiteSearch() {
        // 国家法规库前端检索带不了词 → 必应 site: 落到真结果页（捡回 ADR-0028）。
        let route = router.route(for: anchor(), source: .govLaw)
        #expect(route.kind == .deepLink)
        #expect(route.url?.host == "www.bing.com")
        #expect(route.url?.query?.contains("site:flk.npc.gov.cn") == true)
        #expect(route.query == "《个保法》第24条")           // 原检索词仍随 route 带出
    }

    @Test func pkulaw_paywalled_routesViaBingSiteSearch() {
        // 付费 → 必应 site: 落结果页，每条结果深链进法宝；绝不抓取付费正文。
        let route = router.route(for: anchor(kind: .caseLaw), source: .pkulaw)
        #expect(route.kind == .deepLink)
        #expect(route.url?.host == "www.bing.com")
        #expect(route.url?.query?.contains("site:pkulaw.com") == true)
    }

    @Test func qwenSearch_isModelSearch_noURL() {
        let route = router.route(for: anchor(), source: .qwenSearch)
        #expect(route.kind == .modelSearch)
        #expect(route.url == nil)                        // backend search (Q3) — query only
    }

    @Test func manual_isCopyOnly() {
        let route = router.route(for: anchor(), source: .manual)
        #expect(route.kind == .copyOnly)
        #expect(route.url == nil)
    }

    // MARK: - Defaults + MCP seam

    @Test func defaultSource_byKind() {
        #expect(VerificationQueryRouter.defaultSource(for: .law) == .govLaw)
        #expect(VerificationQueryRouter.defaultSource(for: .caseLaw) == .pkulaw)
        #expect(VerificationQueryRouter.defaultSource(for: .scholarlyArticle) == .baiduScholar)
    }

    @Test func route_prefersAnchorPreferredSource() {
        let route = router.route(for: anchor(kind: .law, sources: [.cnki]))
        #expect(route.source == .cnki)                   // anchor preference beats the kind default
    }

    @Test func mcpRoute_reservesInterfaceOnly() {
        let route = router.mcpRoute(for: anchor())
        #expect(route.kind == .mcpSeam)                  // v0: reserved, not dispatched
        #expect(route.url == nil)
        #expect(route.query == "《个保法》第24条")
    }
}
