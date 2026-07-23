import Foundation

/// The register (语体) a dictation should be cleaned up into, decided by the focus app (460/461).
/// This is the **deterministic floor** of the hybrid: a pure lookup that always works offline and
/// even on weak models; the cloud-judged ceiling (462) layers on top. `.neutral` = today's behavior
/// (no register nudge), so an unknown app is a no-op.
public enum RegisterTier: String, Sendable, Equatable, CaseIterable {
    case chat
    case mail
    case document
    case legal
    case neutral

    /// One short Chinese register nudge fed to the polish prompt by 462 (the deterministic floor).
    /// Register/语体 only — never introduces facts. `.neutral` is empty so 462 appends nothing
    /// (byte-identical to today). Phrasing is intentionally tunable per the #468 A/B.
    public var guidance: String {
        switch self {
        case .chat: "聊天场景：短句、自然、口语，别正式化；可省略客套。"
        case .mail: "邮件场景：完整句、礼貌但不啰嗦、可成段；不杜撰称呼或署名。"
        case .document: "文档场景：书面、清晰结构、用词得体。"
        case .legal: "法律/办案场景：克制、准确、少情绪；宁可朴素，不替用户制造确定性。"
        case .neutral: ""
        }
    }
}

/// Maps the focus app (bundleID / appName / optional browser domain) to a `RegisterTier`.
/// Pure — no network, no AX, no UserDefaults (domain is passed in by 462/463). Deterministic
/// substring table; first match wins; unknown → `.neutral`.
public struct RegisterTierClassifier: Sendable {
    /// Bundle-id substrings for legal / case-handling apps — injectable and minimal-by-default,
    /// since real legal-app bundleIDs are TBD (PRD §7 / 461「先最小种子集，逐步补」).
    private let legalSeeds: Set<String>

    public init(legalSeeds: Set<String> = []) {
        self.legalSeeds = Set(legalSeeds.map { $0.lowercased() })
    }

    /// `domain` is accepted for forward-compat (462 wires the call site once); browser-domain
    /// mapping is #463's job — v1 classifies by bundleID, then appName as a fallback.
    /// 463 — when in a browser the bundleID is generic (Chrome/Safari → neutral); the active tab's
    /// domain carries the register, so it is checked FIRST. Falls back to native bundleID, then
    /// appName, then `.neutral`. `domain` may be a bare host or a full URL (host is extracted).
    public func tier(bundleID: String?, appName: String? = nil, domain: String? = nil) -> RegisterTier {
        matchDomain(domain) ?? match(bundleID) ?? match(appName) ?? .neutral
    }

    private func match(_ value: String?) -> RegisterTier? {
        guard let hay = value?.lowercased(), !hay.isEmpty else { return nil }
        // Legal seeds win first — a configured case app should never be mistaken for chat/doc.
        if legalSeeds.contains(where: { hay.contains($0) }) { return .legal }
        for entry in Self.table where hay.contains(entry.needle) { return entry.tier }
        return nil
    }

    /// 463 — map a browser tab's host → tier via the domain table (legal seeds may also be domains).
    private func matchDomain(_ value: String?) -> RegisterTier? {
        guard let raw = value?.lowercased(), !raw.isEmpty else { return nil }
        let host = URL(string: raw)?.host?.lowercased() ?? raw   // accept a full URL or a bare host
        if legalSeeds.contains(where: { host.contains($0) }) { return .legal }
        for entry in Self.domainTable where host.contains(entry.needle) { return entry.tier }
        return nil
    }

    /// Distinctive bundleID substrings → tier. First match wins, so order specific before broad.
    /// Native-app seeds only; browser web-apps go through `domainTable`. Grow over time.
    private static let table: [(needle: String, tier: RegisterTier)] = [
        // chat（微信 / 企业微信 / 钉钉 / Slack / Messages）
        ("wechat", .chat), ("wework", .chat), ("dingtalk", .chat),
        ("slack", .chat), ("mobilesms", .chat), ("ichat", .chat),
        // mail（Mail / Outlook / Foxmail / Spark）
        ("foxmail", .mail), ("apple.mail", .mail), ("outlook", .mail), ("readdle.smartemail", .mail),
        // document（Word / Pages / Notion / WPS；腾讯文档=web→463）
        ("microsoft.word", .document), ("iwork.pages", .document),
        ("notion", .document), ("wpsoffice", .document),
    ]

    /// 463 — distinctive web-app host substrings → tier (matched against the active tab's host).
    /// First match wins; order specific before broad. Grow over time.
    private static let domainTable: [(needle: String, tier: RegisterTier)] = [
        // chat（网页版 IM）
        ("web.whatsapp.com", .chat), ("wx.qq.com", .chat), ("web.wechat.com", .chat),
        ("web.telegram.org", .chat), ("app.slack.com", .chat), ("discord.com", .chat),
        // mail（网页版邮箱）
        ("mail.google.com", .mail), ("outlook.", .mail), ("outlook.office.com", .mail),
        ("mail.qq.com", .mail), ("mail.163.com", .mail), ("mail.126.com", .mail),
        // document（在线文档）
        ("docs.google.com", .document), ("docs.qq.com", .document), ("notion.so", .document),
        ("feishu.cn", .document), ("larksuite.com", .document), ("yuque.com", .document), ("shimo.im", .document),
        // legal（裁判文书 / 法规 / 法律数据库）
        ("wenshu.court.gov.cn", .legal), ("court.gov.cn", .legal), ("pkulaw.com", .legal),
        ("faxin.cn", .legal), ("chinalawinfo", .legal), ("npc.gov.cn", .legal),
    ]
}
