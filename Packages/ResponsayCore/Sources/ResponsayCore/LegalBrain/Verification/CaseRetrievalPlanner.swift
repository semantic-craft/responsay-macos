import Foundation

/// 474 — 类案检索渠道表（PRD S2）。把案情字段填进分层渠道模板，产出"可执行检索作战图"：每条 = 检索式
/// + 直达 URL。思路取自文章（P0–P3 优先级 + 案号精搜 + filetype:pdf），渠道用我们可信的法律站；URL 走
/// 必应搜索（复用 `VerificationQueryRouter` 的构造）——付费/JS 站的 `site:` 本就是检索式的一部分。

public struct CaseFacts: Sendable, Equatable {
    public var caseNumber: String?    // 案号
    public var causeOfAction: String? // 案由
    public var year: String?          // 年份
    public var keywords: String?      // 关键词
    public var charge: String?        // 罪名

    public init(caseNumber: String? = nil, causeOfAction: String? = nil,
                year: String? = nil, keywords: String? = nil, charge: String? = nil) {
        self.caseNumber = caseNumber; self.causeOfAction = causeOfAction
        self.year = year; self.keywords = keywords; self.charge = charge
    }
}

public struct CaseRetrievalChannel: Sendable, Equatable {
    public let id: String           // 文章渠道码，如 E1-P1-055
    public let tier: Int            // 0=P0(最高) … 3=P3
    public let name: String
    public let expectedCaseNumberRate: Int  // 经验案号率（真机校准）
    let template: String            // 占位 {案号}{案由}{年份}{关键词}{罪名}
}

public struct CaseRetrievalPlan: Sendable, Equatable {
    public let channel: CaseRetrievalChannel
    public let query: String        // 填好的检索式
    public let url: URL?            // 必应搜索直达
}

public enum CaseRetrievalPlanner {
    /// 按 tier 升序产出每个"字段齐全"的渠道的检索式 + URL。缺必需字段的渠道自动跳过。
    public static func plan(_ facts: CaseFacts) -> [CaseRetrievalPlan] {
        channels.sorted { $0.tier < $1.tier }.compactMap { ch in
            guard let q = fill(ch.template, facts) else { return nil }
            return CaseRetrievalPlan(channel: ch, query: q, url: bingURL(q))
        }
    }

    static func bingURL(_ query: String) -> URL? {
        URL(string: "\(VerificationQueryRouter.bingSearchBase)?q=\(VerificationQueryRouter.encodeQueryValue(query))")
    }

    /// 模板里出现的占位都必须有值，否则返回 nil（该渠道这次不可用）。
    static func fill(_ template: String, _ f: CaseFacts) -> String? {
        var s = template
        let map: [(String, String?)] = [
            ("{案号}", f.caseNumber), ("{案由}", f.causeOfAction),
            ("{年份}", f.year), ("{关键词}", f.keywords), ("{罪名}", f.charge),
        ]
        for (placeholder, value) in map where s.contains(placeholder) {
            guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            s = s.replacingOccurrences(of: placeholder, with: value)
        }
        return s
    }

    /// 渠道表（思路取自文章，源用我们可信的法律站；排除反爬直连 wenshu）。新站加一行即可。
    static let channels: [CaseRetrievalChannel] = [
        // P0 — 已知案号最高效
        .init(id: "E1-P0-cn", tier: 0, name: "案号精确检索", expectedCaseNumberRate: 100, template: "\"{案号}\""),
        // P1
        .init(id: "E1-P1-pdf", tier: 1, name: "PDF 判决书", expectedCaseNumberRate: 90, template: "{案由} 判决书 filetype:pdf {年份}"),
        .init(id: "E1-P1-055", tier: 1, name: "律师平台 055110", expectedCaseNumberRate: 95, template: "site:055110.com {案由} {年份} 判决书"),
        .init(id: "E1-P1-rmfy", tier: 1, name: "人民法院案例库", expectedCaseNumberRate: 95, template: "site:rmfyalk.court.gov.cn {关键词}"),
        // 引擎三/四 — 两高典型案例（文章列为最高可靠性官方源；JS 站，走 site: 让用户在自己浏览器打开）
        .init(id: "E3-P1-spc", tier: 1, name: "最高法指导性案例", expectedCaseNumberRate: 95, template: "site:court.gov.cn {关键词} 指导性案例"),
        .init(id: "E4-P1-spp", tier: 1, name: "最高检典型案例", expectedCaseNumberRate: 90, template: "site:spp.gov.cn {关键词} 典型案例"),
        // P2
        .init(id: "E1-P2-fx", tier: 2, name: "法信", expectedCaseNumberRate: 85, template: "site:faxin.cn {关键词}"),
        .init(id: "E1-P2-cc", tier: 2, name: "中国法院网法律文库", expectedCaseNumberRate: 80, template: "site:lawdb.cncourt.org {关键词}"),
        .init(id: "E1-P2-wb", tier: 2, name: "湾区律师网", expectedCaseNumberRate: 80, template: "site:wblaw.com.cn {案由}"),
        // P3 — 线索/弱（案号率低）
        .init(id: "E1-P3-bd", tier: 3, name: "百度法行宝", expectedCaseNumberRate: 40, template: "site:ailegal.baidu.com {罪名} 案例"),
    ]
}
