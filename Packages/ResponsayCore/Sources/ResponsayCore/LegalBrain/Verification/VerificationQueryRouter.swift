import Foundation

// MARK: - 166 Source-verification query routes (seam)
//
// Generates a verification query for a `[待核]` anchor and routes it to the matching
// source. Two deep-link styles, picked per source (ADR-0028「LLM-driven deep links」的
// site: 兜底被捡回为主力):
//   · directSearch — 把检索词塞进该站自己的检索 URL（百度学术 ?wd= / 知网 ?kw= / 必应 ?q=
//     / 万方 ?q= / 维普 ?key= / 无讼 ?searchWord=）。落到该站结果页。
//   · bingSite     — 付费/JS/验证码 站点（北大法宝、国家法规库、人民法院案例库、裁判文书网）
//     自家搜索框带不了词，改用「必应 site:域名 检索词」落到一个真·结果页，每条结果深链进
//     该站对应页（不抓取付费正文，登录态由用户自己浏览器提供）。
// 另有模型内置搜索（Qwen, Q3 seam）与保留的 MCP 接口。core 只产出 route 描述，macOS 层负责
// 打开 URL / 复制检索词。

public enum VerificationRouteKind: String, Sendable, Equatable {
    case deepLink      // open a search-results page (the source's own, or Bing site:)
    case modelSearch   // backend built-in search (Qwen) — query only, Q3 seam
    case mcpSeam       // reserved MCP interface — not dispatched in v0
    case copyOnly      // manual — copy the query, user searches
}

public struct VerificationRoute: Sendable, Equatable {
    public let kind: VerificationRouteKind
    public let source: VerificationSourcePreference
    public let query: String
    public let url: URL?               // present for `.deepLink`

    public init(kind: VerificationRouteKind, source: VerificationSourcePreference, query: String, url: URL?) {
        self.kind = kind
        self.source = source
        self.query = query
        self.url = url
    }
}

public struct VerificationQueryRouter: Sendable {
    public init() {}

    /// 必应检索基址 —— 直达 `.bing` 与所有 `.bingSite` 兜底共用。
    public static let bingSearchBase = "https://www.bing.com/search"

    /// The verification query for an anchor (its seeded query, else its label).
    public func query(for anchor: VerificationAnchor) -> String {
        let q = anchor.query.trimmingCharacters(in: .whitespacesAndNewlines)
        return q.isEmpty ? anchor.label : q
    }

    /// Route an anchor to a source (explicit, else its preferred, else a kind default).
    public func route(for anchor: VerificationAnchor, source: VerificationSourcePreference? = nil) -> VerificationRoute {
        let resolved = source ?? anchor.preferredSources.first ?? Self.defaultSource(for: anchor.kind)
        let q = query(for: anchor)

        switch resolved {
        case .qwenSearch:
            // Backend built-in search (090 / Q3) — carry the query only, no URL.
            return VerificationRoute(kind: .modelSearch, source: resolved, query: q, url: nil)
        case .manual:
            return VerificationRoute(kind: .copyOnly, source: resolved, query: q, url: nil)
        default:
            return VerificationRoute(kind: .deepLink, source: resolved, query: q,
                                     url: Self.searchURL(for: resolved, query: q))
        }
    }

    /// Reserved MCP interface (Open Q6): in v0 this only describes the call, it is not
    /// dispatched. A later phase wires an MCP verification provider behind this seam.
    public func mcpRoute(for anchor: VerificationAnchor) -> VerificationRoute {
        VerificationRoute(kind: .mcpSeam, source: .qwenSearch, query: query(for: anchor), url: nil)
    }

    /// The default source for an anchor kind when none is specified.
    public static func defaultSource(for kind: VerificationKind) -> VerificationSourcePreference {
        switch kind {
        case .scholarlyArticle:                 return .baiduScholar
        case .caseLaw:                          return .pkulaw
        case .law, .administrativeRule, .standard, .officialDocument:
            return .govLaw
        case .date, .money, .other:             return .baiduScholar
        }
    }

    // MARK: - Per-source search style

    /// How a source turns a query into a results-page URL. Defaults are best-known and
    /// **deliberately tunable** — final per-site URLs are confirmed on a real China
    /// browser (issue 216 待核). A source that lands on results in a logged-out browser
    /// uses `.directSearch`; a paywalled/JS/验证码 site uses `.bingSite`.
    enum SearchStyle: Equatable {
        case directSearch(base: String, param: String)
        case bingSite(domain: String)
    }

    static func style(for source: VerificationSourcePreference) -> SearchStyle? {
        switch source {
        case .baiduScholar: return .directSearch(base: "https://xueshu.baidu.com/s", param: "wd")
        case .cnki:         return .directSearch(base: "https://kns.cnki.net/kns8s/defaultresult/index", param: "kw")
        case .webSearch:    return .directSearch(base: "https://www.baidu.com/s", param: "wd")
        case .bing:         return .directSearch(base: bingSearchBase, param: "q")
        case .itslaw:       return .directSearch(base: "https://www.itslaw.com/search", param: "searchWord")
        case .wanfang:      return .directSearch(base: "https://s.wanfangdata.com.cn/paper", param: "q")
        case .vip:          return .directSearch(base: "https://qikan.cqvip.com/Qikan/Search/Index", param: "key")
        case .pkulaw:       return .bingSite(domain: "pkulaw.com")               // 付费 → site:
        case .govLaw:       return .bingSite(domain: "flk.npc.gov.cn")           // JS 前端检索 → site:
        case .rmfyalk:      return .bingSite(domain: "rmfyalk.court.gov.cn")     // JS 前端检索 → site:
        case .wenshu:       return .bingSite(domain: "wenshu.court.gov.cn")      // 验证码 → site:
        case .qwenSearch, .manual:
            return nil                                                          // not URL-routed
        }
    }

    static func searchURL(for source: VerificationSourcePreference, query: String) -> URL? {
        switch style(for: source) {
        case let .directSearch(base, param):
            return makeURL(base: base, param: param, value: query)
        case let .bingSite(domain):
            return makeURL(base: bingSearchBase, param: "q", value: "site:\(domain) \(query)")
        case nil:
            return nil
        }
    }

    private static func makeURL(base: String, param: String, value: String) -> URL? {
        URL(string: "\(base)?\(param)=\(encodeQueryValue(value))")
    }

    /// RFC-3986 query-value encoding that ALSO escapes `+` → `%2B`. A bare `+` left in a
    /// query string is decoded as a space by 百度/Bing, splitting multi-word legal queries
    /// (issue 328). Spaces become `%20`; `&=?#+` are escaped; CJK is percent-encoded.
    static func encodeQueryValue(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=?#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
