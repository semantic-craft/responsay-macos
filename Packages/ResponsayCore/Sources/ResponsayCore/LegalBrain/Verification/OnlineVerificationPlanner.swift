import Foundation

// MARK: - 联网核验 planner（215）
//
// 用户最初诉求：选中文本 → 自动去百度学术 + 北大法宝核对引用是否属实。
// 组合 FactCoordinateExtractor（抽法条/案号/文献…→ [待核] 锚点）+ SearchStrategyGenerator
// （每个锚点 → 各权威源检索式 + 深链）。源开关（百度学术/北大法宝…）过滤路由。
// 人保持在环：本类型只产出「待核清单 + 一键可开的检索深链」，不替用户判定、不抓取。

public struct OnlineVerificationPlan: Sendable {
    public let anchors: [VerificationAnchor]      // 全部 [待核]
    public let strategies: [SearchStrategy]
}

public struct OnlineVerificationPlanner: Sendable {
    public init() {}
    private let extractor = FactCoordinateExtractor()
    private let generator = SearchStrategyGenerator()

    public static let allSources: Set<VerificationSourcePreference> = [.baiduScholar, .pkulaw, .govLaw, .cnki]

    public func plan(selectedText: String, scene: LegalScene = .unknown,
                     enabledSources: Set<VerificationSourcePreference> = OnlineVerificationPlanner.allSources)
    -> OnlineVerificationPlan {
        let anchors = extractor.extract(from: selectedText)
        let strategies = generator.strategies(for: anchors, scene: scene).map { s in
            SearchStrategy(label: s.label, kind: s.kind, primarySource: s.primarySource,
                           routes: s.routes.filter { enabledSources.contains($0.source) },
                           cnkiQuery: enabledSources.contains(.cnki) ? s.cnkiQuery : nil)
        }
        return OnlineVerificationPlan(anchors: anchors, strategies: strategies)
    }
}
