import Testing
import Foundation
@testable import ResponsayCore

@Suite("SelectionVerifyClipboard — only clobber when paste is needed")
struct SelectionVerifyClipboardTests {
    private let router = VerificationQueryRouter()

    private func route(_ source: VerificationSourcePreference) -> VerificationRoute {
        router.route(
            for: VerificationAnchor(id: "a", label: "《民法典》第577条", kind: .law,
                                    status: .pending, query: "民法典 577"),
            source: source)
    }

    /// A bare front-end search page whose URL carries no query — the only case that still
    /// needs a manual paste. Built directly: every routed source now carries the query in
    /// its URL (direct `?param=` or Bing `site:`), so none is param-less anymore.
    private func bareRoute(query: String) -> VerificationRoute {
        VerificationRoute(kind: .deepLink, source: .manual, query: query,
                          url: URL(string: "https://example.gov/search"))
    }

    @Test func paramSources_leaveClipboardUntouched() {
        // 百度学术 / 知网 / 北大法宝(Bing site:) all carry the query in the URL — nothing to paste.
        let routes = [route(.baiduScholar), route(.cnki), route(.pkulaw)]
        #expect(SelectionVerifyClipboard.pasteQuery(openedRoutes: routes) == nil)
    }

    @Test func bareSearchPage_returnsQueryToPaste() {
        let r = bareRoute(query: "民法典 577")
        #expect(r.url?.query == nil)   // sanity: really a bare base URL
        #expect(SelectionVerifyClipboard.pasteQuery(openedRoutes: [r]) == "民法典 577")
    }

    @Test func mixed_returnsThePasteRequiredQuery() {
        let routes = [route(.baiduScholar), bareRoute(query: "民法典 577")]
        #expect(SelectionVerifyClipboard.pasteQuery(openedRoutes: routes) == "民法典 577")
    }

    @Test func routedSources_neverNeedPaste_afterBingSiteFallback() {
        // Regression: govLaw/pkulaw used to open a bare homepage (paste-required); they
        // now route via Bing site: and carry the query — so the clipboard is left alone.
        #expect(SelectionVerifyClipboard.pasteQuery(openedRoutes: [route(.govLaw)]) == nil)
        #expect(SelectionVerifyClipboard.pasteQuery(openedRoutes: [route(.pkulaw)]) == nil)
    }

    @Test func empty_returnsNil() {
        #expect(SelectionVerifyClipboard.pasteQuery(openedRoutes: []) == nil)
    }
}
