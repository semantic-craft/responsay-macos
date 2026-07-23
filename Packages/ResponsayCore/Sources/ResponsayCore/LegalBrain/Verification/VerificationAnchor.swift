import Foundation

// MARK: - [待核] verification anchors
//
// Three-layer source traceability. Any fact coordinate (法条/案号/日期/金额/文献/标准)
// in skill output defaults to `.pending` = [待核]. FactCoordinateExtractor (issue 108)
// produces and back-fills these; the panel renders them as clickable anchors; the
// verification launcher turns them into a search query / deep-link. See spec §8.

public enum VerificationKind: String, Codable, Sendable, CaseIterable {
    case law
    case caseLaw
    case administrativeRule
    case standard
    case scholarlyArticle
    case date
    case money
    case officialDocument
    case other
}

public enum VerificationStatus: String, Codable, Sendable {
    case pending             // [待核]
    case verifiedLaw         // [法条-已核]
    case verifiedCase        // [案例-已核]
    case scholarlyReference  // [学理-参考]
    case userConfirmed       // [用户确认]
    case rejected
}

/// Preferred lookup channels for an anchor. v0 verification = query + open search only
/// (no DB回填); pkulaw/browser回填 land in later phases.
public enum VerificationSourcePreference: String, Codable, Sendable, CaseIterable {
    case govLaw          // flk.npc.gov.cn (公开法规)
    case cnki
    case baiduScholar
    case pkulaw
    case webSearch       // 通用搜索引擎兜底（百度网页）— 新书/译著学术库未收录时
    case bing            // 必应（www.bing.com）— 直达搜索 + 付费/JS 站 site: 限定的承载引擎
    case qwenSearch
    case itslaw           // 无讼 itslaw.com
    case wanfang          // 万方 wanfangdata.com.cn
    case vip              // 维普 cqvip.com
    case rmfyalk          // 人民法院案例库 rmfyalk.court.gov.cn
    case wenshu           // 中国裁判文书网 wenshu.court.gov.cn（付费/验证码 → Bing site: 兜底）
    case manual
}

/// A confirmed source, only present once status leaves `.pending`.
public struct VerifiedSource: Codable, Sendable, Equatable {
    public let title: String
    public let url: String
    public let accessedAt: String
    public let provider: String   // QwenSearch / BaiduScholar / Manual / FutureBrowserExtension
    public let snippet: String?

    public init(title: String, url: String, accessedAt: String, provider: String, snippet: String? = nil) {
        self.title = title
        self.url = url
        self.accessedAt = accessedAt
        self.provider = provider
        self.snippet = snippet
    }
}

public struct VerificationAnchor: Codable, Sendable, Identifiable {
    public let id: String
    public let label: String          // 如 "《民法典》第577条" / "GB/T 39335"
    public let kind: VerificationKind
    public var status: VerificationStatus
    public let query: String
    public let preferredSources: [VerificationSourcePreference]
    public var source: VerifiedSource?

    public init(
        id: String,
        label: String,
        kind: VerificationKind,
        status: VerificationStatus = .pending,
        query: String,
        preferredSources: [VerificationSourcePreference] = [],
        source: VerifiedSource? = nil
    ) {
        self.id = id
        self.label = label
        self.kind = kind
        self.status = status
        self.query = query
        self.preferredSources = preferredSources
        self.source = source
    }
}
