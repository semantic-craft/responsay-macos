import Foundation

// MARK: - 检索策略生成（214 / 共用于 215 联网核验）
//
// 输入法不做 in-app 检索。本类型把「待核锚点 + 情景(LegalScene)」翻译成各权威源的检索式 + 深链：
//   法条/法规  → 国家法规库(flk.npc.gov.cn) + 北大法宝
//   案例/裁判   → 北大法宝
//   学术文献/学说 → 知网 CNKI(专业检索 SU=) + 百度学术
// 深链复用 VerificationQueryRouter（付费源仅打开/复制，不抓取）；全程 [待核]。

public struct SearchStrategy: Sendable {
    public let label: String
    public let kind: VerificationKind
    public let primarySource: VerificationSourcePreference
    public let routes: [VerificationRoute]     // 各源检索深链/检索词
    public let cnkiQuery: CNKIQueryCard?        // 知网专业检索式（学术类）
}

public struct SearchStrategyGenerator: Sendable {
    public init() {}
    private let router = VerificationQueryRouter()

    /// 为一个待核锚点生成检索策略（按 kind + scene 路由到知网/法宝/百度学术/国家法规库）。
    public func strategy(for anchor: VerificationAnchor, scene: LegalScene) -> SearchStrategy {
        let sources = Self.sources(for: anchor.kind, scene: scene)
        let routes = sources.map { router.route(for: anchor, source: $0) }
        let cnki = sources.contains(.cnki) ? cnkiCard(for: anchor) : nil
        return SearchStrategy(label: anchor.label, kind: anchor.kind,
                              primarySource: sources.first ?? .baiduScholar,
                              routes: routes, cnkiQuery: cnki)
    }

    public func strategies(for anchors: [VerificationAnchor], scene: LegalScene) -> [SearchStrategy] {
        anchors.map { strategy(for: $0, scene: scene) }
    }

    /// 来源路由（迁移自得理 search know-how，输出端换成知网/法宝/百度学术/国家法规库）。
    static func sources(for kind: VerificationKind, scene: LegalScene) -> [VerificationSourcePreference] {
        switch kind {
        case .scholarlyArticle:
            // 知网 → 百度学术 → 搜索引擎兜底（新出译著/专著学术库常未收录，兜底直达出版社/书目页）
            return [.cnki, .baiduScholar, .webSearch]
        case .law, .administrativeRule, .standard, .officialDocument:
            return [.govLaw, .pkulaw]
        case .caseLaw:
            return [.pkulaw]
        case .date, .money, .other:
            // 学术写作场景下，泛主题/学说优先走知网+百度学术
            return scene == .academicWriting ? [.cnki, .baiduScholar] : [.baiduScholar]
        }
    }

    /// 知网专业检索式：走 `CNKIExpertQueryBuilder`（移植自 opencli 已验证实现）。
    /// 主题词 → `SU %= '词'`（多词以「 * 」组合），词内单引号转义为 ''。
    private func cnkiCard(for anchor: VerificationAnchor) -> CNKIQueryCard {
        let raw = anchor.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let plain = raw.isEmpty ? anchor.label : raw
        let expert = CNKIExpertQueryBuilder.build(query: plain)
        return CNKIQueryCard(title: "知网专业检索式", expertQuery: expert, plainQuery: plain)
    }
}
