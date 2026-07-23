import Testing
import Foundation
@testable import ResponsayCore

// MARK: - Bing direct + `site:` fallback routing (ADR-0028 revived) + query encoding (328)

struct VerificationSiteSearchTests {
    private let router = VerificationQueryRouter()

    private func anchor(
        label: String = "测试",
        kind: VerificationKind = .other,
        query: String = "",
        sources: [VerificationSourcePreference] = []
    ) -> VerificationAnchor {
        VerificationAnchor(id: "a", label: label, kind: kind, query: query, preferredSources: sources)
    }

    // MARK: - New enum cases

    @Test func bing_and_wenshu_casesExist() {
        #expect(VerificationSourcePreference.bing.rawValue == "bing")
        #expect(VerificationSourcePreference.wenshu.rawValue == "wenshu")
    }

    // MARK: - Bing direct search

    @Test func bing_directSearch_usesQParam() throws {
        let route = router.route(for: anchor(query: "比例原则 公法"), source: .bing)
        #expect(route.kind == .deepLink)
        let url = try #require(route.url)
        #expect(url.host == "www.bing.com")
        #expect(url.path == "/search")
        #expect(url.query?.hasPrefix("q=") == true)
        #expect(url.query?.contains("site:") == false)   // direct search, not a site: constraint
    }

    // MARK: - `site:` fallback for paywalled / JS sources

    @Test func wenshu_routesViaBingSiteSearch() throws {
        let route = router.route(for: anchor(kind: .caseLaw, query: "(2021)京01民终123号", sources: [.wenshu]))
        let url = try #require(route.url)
        #expect(url.host == "www.bing.com")
        #expect(url.query?.contains("site:wenshu.court.gov.cn") == true)
    }

    @Test func siteSearch_carriesTheQueryAfterTheSiteConstraint() throws {
        // The results page must actually search for the anchor, not just open the domain.
        let route = router.route(for: anchor(kind: .caseLaw, query: "缔约过失责任", sources: [.pkulaw]))
        let url = try #require(route.url)
        let decoded = url.query?.removingPercentEncoding ?? ""
        #expect(decoded.contains("site:pkulaw.com"))
        #expect(decoded.contains("缔约过失责任"))
    }

    // MARK: - Query-value encoding (328: bare `+` is read as a space by 百度/Bing)

    @Test func plusSign_isEscapedNotLeftBare() {
        let encoded = VerificationQueryRouter.encodeQueryValue("C++ 合同法")
        #expect(encoded.contains("%2B"))
        #expect(encoded.contains("+") == false)   // never a bare '+'
    }

    @Test func spaces_becomePercent20() {
        let encoded = VerificationQueryRouter.encodeQueryValue("合同 解除")
        #expect(encoded.contains("%20"))
        #expect(encoded.contains("+") == false)
    }

    @Test func builtURL_isParseableWithCJKAndPlus() throws {
        // A real selection query (CJK + punctuation) must still build a valid URL.
        let route = router.route(for: anchor(query: "《民法典》第577条 + 违约责任", sources: [.baiduScholar]))
        let url = try #require(route.url)
        #expect(url.host == "xueshu.baidu.com")
        #expect(url.absoluteString.contains("%2B"))   // the literal '+' in the query is escaped
    }
}
