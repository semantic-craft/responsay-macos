import Testing
import Foundation
@testable import ResponsayCore

// 检索策略生成：情景感知 + 待核锚点 → 按源路由生成知网/法宝/百度学术检索式 + 深链。
// 法条→国家法规库/法宝；案例→法宝；学术文献→知网(专业检索)/百度学术。
@Suite("检索策略生成")
struct SearchStrategyGeneratorTests {
    let gen = SearchStrategyGenerator()

    private func anc(_ label: String, _ kind: VerificationKind, _ query: String? = nil) -> VerificationAnchor {
        VerificationAnchor(id: "a", label: label, kind: kind, query: query ?? label)
    }

    private func urls(_ s: SearchStrategy) -> [String] { s.routes.compactMap { $0.url?.absoluteString } }

    @Test("学术文献 → CNKI 专业检索式 + 知网/百度学术深链")
    func scholarly() {
        let s = gen.strategy(for: anc("个人信息保护 同意", .scholarlyArticle), scene: .academicWriting)
        #expect(s.primarySource == .cnki)
        #expect(s.cnkiQuery?.expertQuery.contains("SU %=") == true)   // 相关匹配运算符
        #expect(urls(s).contains { $0.contains("kns.cnki.net") })
        #expect(urls(s).contains { $0.contains("xueshu.baidu.com") })
    }

    @Test("法条 → 国家法规库 + 北大法宝（无 CNKI 专业检索）")
    func law() {
        let s = gen.strategy(for: anc("《民法典》第577条", .law, "民法典 577"), scene: .litigation)
        #expect(s.primarySource == .govLaw)
        #expect(s.cnkiQuery == nil)
        #expect(urls(s).contains { $0.contains("flk.npc.gov.cn") })
        #expect(urls(s).contains { $0.contains("pkulaw.com") })
    }

    @Test("案例 → 北大法宝")
    func caseLaw() {
        let s = gen.strategy(for: anc("(2021)最高法民申1234号", .caseLaw), scene: .litigation)
        #expect(s.primarySource == .pkulaw)
        #expect(urls(s).contains { $0.contains("pkulaw.com") })
    }

    @Test("学术写作场景：泛主题也走知网+百度学术")
    func academicOther() {
        let s = gen.strategy(for: anc("数据财产权学说", .other), scene: .academicWriting)
        #expect(s.primarySource == .cnki)
        #expect(s.cnkiQuery != nil)
    }

    // 词内单引号（Law's Empire / Hart's…）转义为 ''（CNKI 专业检索的合法写法），
    // 保住外层 '…' 引号配对——比旧实现「直接删撇号」更忠实（移植自 opencli）。
    @Test("英文文献词内单引号被转义为 ''")
    func scholarlyApostropheEscaped() {
        let s = gen.strategy(for: anc("Law's Empire", .scholarlyArticle), scene: .academicWriting)
        #expect(s.cnkiQuery?.expertQuery == "SU %= 'Law''s' * 'Empire'")
    }

    @Test("批量生成")
    func batch() {
        let ss = gen.strategies(for: [anc("《个保法》第24条", .law), anc("算法歧视", .scholarlyArticle)],
                                scene: .academicWriting)
        #expect(ss.count == 2)
    }
}
