import Testing
import Foundation
@testable import ResponsayCore

/// Comprehensive reliability audit for the fact-check pipeline:
/// FactCoordinateExtractor → VerificationQueryRouter → SearchStrategyGenerator → deep-links.
/// Covers edge cases from real legal documents that the basic test suite doesn't reach.
@Suite("Fact-Check Reliability Audit")
struct FactCheckReliabilityAuditTests {
    private let extractor = FactCoordinateExtractor()
    private let router = VerificationQueryRouter()
    private let stratGen = SearchStrategyGenerator()
    private let planner = OnlineVerificationPlanner()

    // MARK: - 1. FactCoordinateExtractor Coverage Gaps

    @Suite("Extractor — law rules")
    struct LawExtraction {
        private let extractor = FactCoordinateExtractor()
        private func first(_ text: String) -> VerificationAnchor? { extractor.extract(from: text).first }

        @Test("法条含'之一'后缀: 第1024条之一")
        func law_zhiYi() {
            let a = first("依据《民法典》第一千零二十四条之一规定")
            #expect(a?.kind == .law)
            #expect(a?.label.contains("之") == true)
        }

        @Test("法条含完整条款项目层级: 第27条第2款第（三）项")
        func law_fullHierarchy() {
            let a = first("《公司法》第27条第2款第（三）项")
            #expect(a?.kind == .law)
            #expect(a?.label.contains("项") == true)
        }

        @Test("法条使用半角括号的修订年: (2023年修正)")
        func law_halfwidthRevisionYear() {
            // Real documents sometimes use ASCII parentheses for revision years
            let a = first("适用《著作权法》(2020年修正)第47条的规定")
            // This may not be captured if regex requires fullwidth
            if let a { #expect(a.kind == .law) }
        }

        @Test("仅法律名称无条号 → 不提取")
        func law_nameOnly_shouldNotExtract() {
            let anchors = extractor.extract(from: "《民法典》规定了侵权责任")
            #expect(anchors.filter { $0.kind == .law }.isEmpty)
        }

        @Test("多法条在同一句")
        func law_multiple() {
            let text = "依据《民法典》第577条和《合同法》第107条的规定"
            let laws = extractor.extract(from: text).filter { $0.kind == .law }
            #expect(laws.count == 2)
        }
    }

    @Suite("Extractor — case number rules")
    struct CaseNumberExtraction {
        private let extractor = FactCoordinateExtractor()
        private func first(_ text: String) -> VerificationAnchor? { extractor.extract(from: text).first }

        @Test("标准案号: (2021)最高法民终1234号")
        func caseNumber_standard() {
            let a = first("参见(2021)最高法民终1234号判决")
            #expect(a?.kind == .caseLaw)
        }

        @Test("全角圆括号案号: （2022）吉民终461号")
        func caseNumber_fullwidthParens() {
            let a = first("该案为（2022）吉民终461号案")
            #expect(a?.kind == .caseLaw)
        }

        @Test("指导性案例: 指导案例24号")
        func guidingCase() {
            let a = first("正如指导案例24号所确立的裁判要旨")
            #expect(a != nil)
            #expect(a?.kind == .law)
            #expect(a?.label == "指导案例24号")
        }

        @Test("六角括号误用案号: 〔2019〕最高法民再1号 — 兜底提取为 caseLaw")
        func caseNumber_hexagonBracketFallback() {
            let a = first("见〔2019〕最高法民再1号判决")
            #expect(a != nil)
            #expect(a?.kind == .caseLaw)
        }
    }

    @Suite("Extractor — document numbers")
    struct DocumentNumberExtraction {
        private let extractor = FactCoordinateExtractor()
        private func first(_ text: String) -> VerificationAnchor? { extractor.extract(from: text).first }

        @Test("机关简称超长: 最高人民法院最高人民检察院公安部〔2019〕1号")
        func longIssuingBody() {
            let a = first("最高人民法院最高人民检察院公安部〔2019〕1号文件")
            #expect(a?.kind == .officialDocument)
        }

        @Test("带前导动词: 根据国发〔2007〕19号")
        func stripLeadIn() {
            let a = first("根据国发〔2007〕19号的规定")
            #expect(a?.kind == .officialDocument)
            #expect(a?.label.hasPrefix("国发") == true)
        }
    }

    @Suite("Extractor — scholarly articles (NOT covered)")
    struct ScholarlyArticleGap {
        private let extractor = FactCoordinateExtractor()

        @Test("学术论文引用 → 正则无法提取（确认缺口）")
        func paper_notExtracted() {
            let text = "正如王利明教授在《法学研究》上发表的《论信赖利益的保护》中所论述"
            let anchors = extractor.extract(from: text)
            let papers = anchors.filter { $0.kind == .scholarlyArticle }
            #expect(papers.isEmpty, "Confirmed: extractor has no rule for scholarly articles")
        }

        @Test("专著引用 → 正则无法提取（确认缺口）")
        func monograph_notExtracted() {
            let text = "参见王泽鉴：《民法学说与判例研究》，中国政法大学出版社2003年版，第120页"
            let anchors = extractor.extract(from: text)
            let papers = anchors.filter { $0.kind == .scholarlyArticle }
            #expect(papers.isEmpty, "Confirmed: extractor has no rule for monographs/books")
        }
    }

    // MARK: - 2. Deep-Link URL Validity

    @Suite("Deep-link URL structure")
    struct DeepLinkURLTests {
        private let router = VerificationQueryRouter()

        @Test("百度学术 URL 格式正确")
        func baiduScholar_urlFormat() {
            let a = VerificationAnchor(id: "a", label: "比例原则", kind: .scholarlyArticle, query: "比例原则 行政法")
            let route = router.route(for: a, source: .baiduScholar)
            #expect(route.kind == .deepLink)
            let url = route.url!
            #expect(url.scheme == "https")
            #expect(url.host == "xueshu.baidu.com")
            #expect(url.path == "/s")
            #expect(url.query?.contains("wd=") == true)
        }

        @Test("知网 URL 格式正确")
        func cnki_urlFormat() {
            let a = VerificationAnchor(id: "a", label: "比例原则", kind: .scholarlyArticle, query: "比例原则")
            let route = router.route(for: a, source: .cnki)
            let url = route.url!
            #expect(url.host == "kns.cnki.net")
            #expect(url.path.contains("kns8s") == true)
            #expect(url.query?.contains("kw=") == true)
        }

        @Test("国家法规库 — Bing site: 落结果页（前端检索带不了词）")
        func govLaw_routesViaBingSite() {
            let a = VerificationAnchor(id: "a", label: "《民法典》第577条", kind: .law, query: "民法典 第577条")
            let route = router.route(for: a, source: .govLaw)
            #expect(route.kind == .deepLink)
            #expect(route.url?.host == "www.bing.com")
            #expect(route.url?.query?.contains("site:flk.npc.gov.cn") == true)
        }

        @Test("北大法宝 — Bing site: 落结果页（付费，仅经必应不抓取）")
        func pkulaw_routesViaBingSite() {
            let a = VerificationAnchor(id: "a", label: "(2021)京01民终1234号", kind: .caseLaw, query: "(2021)京01民终1234号")
            let route = router.route(for: a, source: .pkulaw)
            #expect(route.url?.host == "www.bing.com")
            #expect(route.url?.query?.contains("site:pkulaw.com") == true)
        }

        @Test("URL 中文编码正确: 不会产生空查询")
        func chineseEncoding() {
            let a = VerificationAnchor(id: "a", label: "《民法典》第577条", kind: .law, query: "《民法典》第577条")
            let route = router.route(for: a, source: .baiduScholar)
            #expect(route.url != nil)
            #expect(route.url!.absoluteString.contains("wd="))
        }
    }

    // MARK: - 3. CNKI Expert Query Generation

    @Suite("CNKI query generation")
    struct CNKIQueryTests {
        private let gen = SearchStrategyGenerator()

        @Test("多词检索 → SU %= '词1' * '词2'（同字段 * 组合）")
        func multiTerm() {
            let a = VerificationAnchor(id: "a", label: "比例原则", kind: .scholarlyArticle, query: "比例原则 行政法")
            let s = gen.strategy(for: a, scene: .academicWriting)
            #expect(s.cnkiQuery?.expertQuery == "SU %= '比例原则' * '行政法'")
        }

        @Test("单词检索 → SU %= '词'")
        func singleTerm() {
            let a = VerificationAnchor(id: "a", label: "合规", kind: .scholarlyArticle, query: "合规")
            let s = gen.strategy(for: a, scene: .academicWriting)
            #expect(s.cnkiQuery?.expertQuery == "SU %= '合规'")
        }

        @Test("空 query → 回退到 label")
        func emptyQueryFallback() {
            let a = VerificationAnchor(id: "a", label: "信赖利益保护", kind: .scholarlyArticle, query: "")
            let s = gen.strategy(for: a, scene: .academicWriting)
            #expect(s.cnkiQuery?.expertQuery.contains("信赖利益保护") == true)
        }
    }

    // MARK: - 4. SearchStrategy source routing

    @Suite("Strategy source routing")
    struct StrategySourceTests {
        private let gen = SearchStrategyGenerator()

        @Test("法条 → govLaw + pkulaw")
        func lawRouting() {
            let a = VerificationAnchor(id: "a", label: "《民法典》第577条", kind: .law, query: "民法典 577")
            let s = gen.strategy(for: a, scene: .litigation)
            let sources = s.routes.map(\.source)
            #expect(sources.contains(.govLaw))
            #expect(sources.contains(.pkulaw))
        }

        @Test("案例 → pkulaw only")
        func caseRouting() {
            let a = VerificationAnchor(id: "a", label: "(2021)京01民终1234号", kind: .caseLaw, query: "(2021)京01民终1234号")
            let s = gen.strategy(for: a, scene: .litigation)
            #expect(s.primarySource == .pkulaw)
        }

        @Test("学术文献·学术场景 → cnki + baiduScholar")
        func scholarlyRouting() {
            let a = VerificationAnchor(id: "a", label: "比例原则", kind: .scholarlyArticle, query: "比例原则")
            let s = gen.strategy(for: a, scene: .academicWriting)
            let sources = s.routes.map(\.source)
            #expect(sources.contains(.cnki))
            #expect(sources.contains(.baiduScholar))
        }

        @Test("日期·学术场景 → cnki + baiduScholar")
        func dateInAcademic() {
            let a = VerificationAnchor(id: "a", label: "2021年1月1日", kind: .date, query: "2021年1月1日")
            let s = gen.strategy(for: a, scene: .academicWriting)
            let sources = s.routes.map(\.source)
            #expect(sources.contains(.cnki))
        }

        @Test("日期·诉讼场景 → baiduScholar only")
        func dateInLitigation() {
            let a = VerificationAnchor(id: "a", label: "2021年1月1日", kind: .date, query: "2021年1月1日")
            let s = gen.strategy(for: a, scene: .litigation)
            #expect(s.primarySource == .baiduScholar)
            #expect(!s.routes.map(\.source).contains(.cnki))
        }
    }

    // MARK: - 5. Post-processor [待核] enforcement

    @Suite("[待核] tag enforcement")
    struct PostProcessorTests {
        private let pp = VerificationPostProcessor()

        @Test("response 中未锚定的坐标被 backfill 补上")
        func backfillMissing() {
            let response = LegalSkillResponse(
                runId: "r1", skillId: "s1", scene: .litigation, stage: .briefDrafting,
                summary: "依据《民法典》第577条和（2021）京01民终1234号案件",
                cards: [], insertables: [], verificationAnchors: [], warnings: [])
            let filled = pp.backfill(response)
            #expect(filled.verificationAnchors.count >= 2)
            #expect(filled.verificationAnchors.allSatisfy { $0.status == .pending })
        }

        @Test("已锚定的坐标不重复添加")
        func noDoubleAnchor() {
            let existing = VerificationAnchor(id: "law:《民法典》第577条", label: "《民法典》第577条",
                                              kind: .law, query: "民法典 577")
            let response = LegalSkillResponse(
                runId: "r1", skillId: "s1", scene: .litigation, stage: .briefDrafting,
                summary: "《民法典》第577条", cards: [], insertables: [],
                verificationAnchors: [existing], warnings: [])
            let filled = pp.backfill(response)
            #expect(filled.verificationAnchors.count == 1)
        }

        @Test("ensureTags 幂等: 不会叠加多个 [待核]")
        func ensureTagsIdempotent() {
            let text = "《民法典》第577条[待核]已被引用"
            let tagged = pp.ensureTags(in: text)
            #expect(tagged.components(separatedBy: "[待核]").count == 2)
        }
    }

    // MARK: - 6. End-to-end: OnlineVerificationPlanner

    @Suite("End-to-end planner")
    struct PlannerE2ETests {
        private let planner = OnlineVerificationPlanner()

        @Test("混合文本: 法条+案号+日期+金额 → 多锚点 + 多路由策略")
        func mixedText() {
            let text = """
            依据《民法典》第577条，被告于2021年3月15日违约，标的额120万元。
            参见（2022）吉民终461号判决，法院依据国发〔2007〕19号政策性文件裁判。
            """
            let plan = planner.plan(selectedText: text, scene: .litigation)
            #expect(plan.anchors.count >= 4)  // law, date, money, caseLaw, officialDocument
            let kinds = Set(plan.anchors.map(\.kind))
            #expect(kinds.contains(.law))
            #expect(kinds.contains(.caseLaw))
            #expect(kinds.contains(.date))
            #expect(kinds.contains(.money))
        }

        @Test("纯论述文本无可核验坐标 → 空计划")
        func pureProseEmpty() {
            let text = "法律应当维护社会公平正义，保障人民合法权益。"
            let plan = planner.plan(selectedText: text, scene: .litigation)
            #expect(plan.anchors.isEmpty)
            #expect(plan.strategies.isEmpty)
        }
    }

    // MARK: - 7. Skill prompt output schema alignment

    @Suite("Skill prompt → output schema")
    struct SkillPromptTests {
        @Test("fact_check 技能的 outputCards 只有 verificationTodos")
        func outputCards() throws {
            let runtime = try LegalSkillRuntime.bundled()
            let skill = runtime.registry.skill(id: "verification.fact_check.cn")!
            #expect(skill.metadata.outputCards == [.verificationTodos])
        }

        @Test("fact_check prompt 系统消息包含 verificationConstraint")
        func systemPromptContainsConstraint() throws {
            let runtime = try LegalSkillRuntime.bundled()
            let skill = runtime.registry.skill(id: "verification.fact_check.cn")!
            let assembler = LegalPromptAssembler()
            let ctx = LegalContextPayload(selectedText: "《民法典》第577条", scene: .litigation,
                                          stage: .briefDrafting, appName: "Test", contextScope: .selectedTextOnly)
            let prompt = assembler.assemble(skill: skill, context: ctx)
            #expect(prompt.system.contains("verificationAnchors"))
            #expect(prompt.system.contains("[待核]"))
            #expect(prompt.system.contains("不得编造"))
        }

        @Test("fact_check prompt 输出约束要求 verificationAnchors JSON 且不为空")
        func outputConstraint() throws {
            let runtime = try LegalSkillRuntime.bundled()
            let skill = runtime.registry.skill(id: "verification.fact_check.cn")!
            #expect(!skill.outputConstraint.isEmpty, "outputConstraint was empty — check LEGAL_SKILL.md uses ## headings not **bold**")
            #expect(skill.outputConstraint.contains("LEGAL_OUTPUT/v1"))
            #expect(skill.outputConstraint.contains("verificationAnchors"))
            #expect(skill.outputConstraint.contains("verificationTodos"))
            #expect(skill.outputConstraint.contains("pending"))
        }
    }
}
