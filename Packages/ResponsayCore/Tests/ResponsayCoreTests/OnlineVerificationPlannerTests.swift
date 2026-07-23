import Testing
import Foundation
@testable import ResponsayCore

// 联网核验：选中文本 → 抽待核锚点 → 每个生成知网/法宝/百度学术检索策略（受源开关过滤）。
@Suite("联网核验 planner")
struct OnlineVerificationPlannerTests {
    let planner = OnlineVerificationPlanner()

    @Test("选中含法条 → 待核锚点（全 [待核]）+ 法宝/国家法规库检索策略")
    func plan() {
        let p = planner.plan(selectedText: "依据《民法典》第577条，违约方应承担继续履行责任。", scene: .litigation)
        #expect(!p.anchors.isEmpty)
        #expect(p.anchors.allSatisfy { $0.status == .pending })
        let urls = p.strategies.flatMap { $0.routes.compactMap { $0.url?.absoluteString } }
        #expect(urls.contains { $0.contains("pkulaw.com") || $0.contains("flk.npc.gov.cn") })
    }

    @Test("关掉北大法宝 → 策略不含法宝深链")
    func toggleOff() {
        let p = planner.plan(selectedText: "《民法典》第577条", scene: .litigation,
                             enabledSources: [.govLaw, .baiduScholar])
        let hasPkulaw = p.strategies.flatMap { $0.routes }.contains { $0.source == .pkulaw }
        #expect(!hasPkulaw)
    }

    @Test("无可核验坐标 → 空计划")
    func empty() {
        let p = planner.plan(selectedText: "今天天气不错。", scene: .unknown)
        #expect(p.anchors.isEmpty)
        #expect(p.strategies.isEmpty)
    }
}
