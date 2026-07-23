import Testing
import Foundation
@testable import ResponsayCore

// MARK: - 来源核验 source menu: verify ANY selection, pick the source

struct SelectionVerifyMenuTests {
    private let menu = SelectionVerifyMenu()

    private func groupTitles(_ groups: [VerifyMenuGroup]) -> [String] { groups.map(\.title) }

    private func item(_ groups: [VerifyMenuGroup], group: String, source: VerificationSourcePreference) -> VerifyMenuItem? {
        groups.first { $0.title == group }?.items.first { $0.source == source }
    }

    // MARK: - Verify-anything (no gating)

    @Test func plainProse_noAnchors_stillOffersAllGroups() {
        // 一段普通论述，没有任何法条/案号 → 仍然给全部四组源（核心诉求：选中就能核验）。
        let groups = menu.build(selectedText: "这段话的来源我想核实一下，看看到底是不是这么回事。")
        #expect(groupTitles(groups) == ["法规", "案例", "文献", "兜底"])
    }

    @Test func plainProse_routesCarryWholeSelectionQuery() throws {
        let text = "缔约过失责任的赔偿范围"
        let groups = menu.build(selectedText: text)
        let baidu = try #require(item(groups, group: "文献", source: .baiduScholar))
        let decoded = baidu.route.url?.query?.removingPercentEncoding ?? ""
        #expect(decoded.contains(text))            // 整段选区当检索词
    }

    @Test func emptySelection_emptyMenu() {
        #expect(menu.build(selectedText: "   \n  ").isEmpty)
    }

    // MARK: - Precise anchors used when present

    @Test func lawAnchor_lawGroupUsesCoordinateNotProse() throws {
        let anchor = VerificationAnchor(
            id: "l", label: "《民法典》第577条", kind: .law,
            query: "《民法典》第577条")
        let groups = menu.build(selectedText: "依据《民法典》第577条，违约方应当承担继续履行等责任。",
                                anchors: [anchor])
        let fabao = try #require(item(groups, group: "法规", source: .pkulaw))
        let decoded = fabao.route.url?.query?.removingPercentEncoding ?? ""
        #expect(decoded.contains("site:pkulaw.com"))
        #expect(decoded.contains("《民法典》第577条"))     // 精准坐标，而非整段
    }

    @Test func caseAnchor_caseGroupUsesCaseNumber() throws {
        let anchor = VerificationAnchor(
            id: "c", label: "(2021)京01民终123号", kind: .caseLaw,
            query: "(2021)京01民终123号")
        let groups = menu.build(selectedText: "参见(2021)京01民终123号判决。", anchors: [anchor])
        let wenshu = try #require(item(groups, group: "案例", source: .wenshu))
        let decoded = wenshu.route.url?.query?.removingPercentEncoding ?? ""
        #expect(decoded.contains("site:wenshu.court.gov.cn"))
        #expect(decoded.contains("(2021)京01民终123号"))
    }

    // MARK: - Group composition + names

    @Test func groups_listExpectedSourcesAndNames() throws {
        let groups = menu.build(selectedText: "测试文本")
        #expect(item(groups, group: "法规", source: .govLaw)?.title == "国家法规库")
        #expect(item(groups, group: "法规", source: .pkulaw)?.title == "北大法宝")
        #expect(item(groups, group: "案例", source: .itslaw)?.title == "无讼")
        #expect(item(groups, group: "案例", source: .wenshu)?.title == "裁判文书网")
        #expect(item(groups, group: "文献", source: .cnki)?.title == "知网·关键词")
        #expect(item(groups, group: "文献", source: .vip)?.title == "维普")
        #expect(item(groups, group: "文献", source: .wanfang)?.title == "万方")
        #expect(item(groups, group: "兜底", source: .bing)?.title == "必应")
        #expect(item(groups, group: "兜底", source: .webSearch)?.title == "百度")
    }

    // MARK: - CNKI splits into keyword + professional-expression items

    @Test func cnki_splitsIntoKeywordAndExpert() throws {
        let groups = menu.build(selectedText: "比例原则 行政法")
        let lit = try #require(groups.first { $0.title == "文献" })
        let cnkiTitles = lit.items.filter { $0.source == .cnki }.map(\.title)
        #expect(cnkiTitles == ["知网·关键词", "知网·专业检索式"])

        // 关键词项 → 一框式 ?kw= 直达
        let keyword = try #require(lit.items.first { $0.title == "知网·关键词" })
        #expect(keyword.route.url?.host == "kns.cnki.net")
        #expect(keyword.route.url?.query?.contains("kw=") == true)

        // 专业检索式项 → 开 AdvSearch 页 + route.query = 生成的检索式
        let expert = try #require(lit.items.first { $0.title == "知网·专业检索式" })
        #expect(expert.route.url?.absoluteString == "https://kns.cnki.net/kns8s/AdvSearch")
        #expect(expert.route.query == "SU %= '比例原则' * '行政法'")
        // AdvSearch 无 query string → 打开时检索式被复制到剪贴板供粘贴
        #expect(SelectionVerifyClipboard.pasteQuery(openedRoutes: [expert.route]) == "SU %= '比例原则' * '行政法'")
    }

    // MARK: - Long-selection truncation (issue 328)

    @Test func longSelection_truncatedToCap() {
        let long = String(repeating: "中", count: 300)
        let q = SelectionVerifyMenu.normalizeSelection(long)
        #expect(q.count == SelectionVerifyMenu.maxSelectionQueryLength)
    }

    @Test func normalize_collapsesWhitespaceAndNewlines() {
        let q = SelectionVerifyMenu.normalizeSelection("合同   解除\n  权利")
        #expect(q == "合同 解除 权利")
    }
}
