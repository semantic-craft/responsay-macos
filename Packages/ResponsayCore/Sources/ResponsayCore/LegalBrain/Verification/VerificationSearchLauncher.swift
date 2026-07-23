import Foundation

// MARK: - 108 VerificationSearchLauncher
//
// Turns a pending `[待核]` anchor into a one-click SEARCH ENTRY — a deep-link or a
// copyable query. It never claims the source is verified and never fabricates one:
// it only opens a search the user runs themselves. Core produces the URL/query;
// the macOS layer does `NSWorkspace.open`. Backend (Qwen) search is Q3 (090).

public struct VerificationSearchLauncher: Sendable {
    public init() {}

    /// A copyable query string (also the Qwen-search request text when 090/Q3 lands).
    public func copyableQuery(for anchor: VerificationAnchor) -> String {
        anchor.query.isEmpty ? anchor.label : anchor.query
    }

    /// 百度学术 deep-link (scholarly sources).
    public func baiduScholarURL(for anchor: VerificationAnchor) -> URL? {
        Self.search("https://xueshu.baidu.com/s", param: "wd", query: copyableQuery(for: anchor))
    }

    /// General web search (laws / standards / cases — no paywalled DB assumed).
    public func webSearchURL(for anchor: VerificationAnchor) -> URL? {
        Self.search("https://www.baidu.com/s", param: "wd", query: copyableQuery(for: anchor))
    }

    /// The best default entry for an anchor: scholarly → 百度学术; everything else → web search.
    /// (Paywalled DB回填 — pkulaw/CNKI deep-decode — is a later phase.)
    public func primaryURL(for anchor: VerificationAnchor) -> URL? {
        switch anchor.kind {
        case .scholarlyArticle:
            return baiduScholarURL(for: anchor)
        case .law, .caseLaw, .administrativeRule, .standard, .officialDocument, .date, .money, .other:
            return webSearchURL(for: anchor)
        }
    }

    private static func search(_ base: String, param: String, query: String) -> URL? {
        var components = URLComponents(string: base)
        components?.queryItems = [URLQueryItem(name: param, value: query)]
        return components?.url
    }
}
