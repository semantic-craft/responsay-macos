import Testing
@testable import ResponsayCore

@Suite("487 · 检索作战图 post-processor（LLM 焦点 → 确定性作战图卡片）")
struct CaseRetrievalReportPostProcessorTests {

    private func response(cards: [LegalOutputCard]) -> LegalSkillResponse {
        LegalSkillResponse(
            runId: "r", skillId: "research.case_retrieval_report.cn",
            scene: .litigation, stage: .postRetrievalSynthesis, summary: "", cards: cards)
    }

    private var oneFocus: LegalOutputCard {
        .caseFacts(CaseFactsCard(title: "检索焦点", focuses: [
            CaseFactsFocus(id: "f1", label: "竞业限制补偿金未支付的法律效果",
                           causeOfAction: "竞业限制纠纷", year: "2023", keywords: "竞业限制 补偿金"),
        ]))
    }

    @Test("焦点卡片 → 输出含确定性作战图卡片（带安全降级提示）")
    func buildsRetrievalReportCard() {
        let out = CaseRetrievalReportPostProcessor.process(response(cards: [oneFocus]))
        let report = out.cards.compactMap { card -> CaseRetrievalReportCard? in
            if case let .caseRetrievalReport(c) = card { return c }; return nil
        }.first
        #expect(report != nil)
        #expect(report?.markdown.contains("⚠️") == true)
        #expect(report?.markdown.contains("竞业限制补偿金未支付的法律效果") == true)
    }

    @Test("原始焦点卡片被替换：输出不再含 caseFacts 卡片")
    func consumesCaseFactsCard() {
        let out = CaseRetrievalReportPostProcessor.process(response(cards: [oneFocus]))
        let stillHasFacts = out.cards.contains { if case .caseFacts = $0 { return true }; return false }
        #expect(stillHasFacts == false)
    }

    @Test("无焦点卡片：响应原样返回，不凭空加作战图")
    func passesThroughWithoutCaseFacts() {
        let analysis = LegalOutputCard.legalAnalysis(
            LegalAnalysisCard(title: "法律分析", items: [LegalAnalysisItem(id: "i1", label: "x", content: "y")]))
        let out = CaseRetrievalReportPostProcessor.process(response(cards: [analysis]))
        let hasReport = out.cards.contains { if case .caseRetrievalReport = $0 { return true }; return false }
        #expect(hasReport == false)
        #expect(out.cards.count == 1)
    }

    @Test("多焦点聚合为一张作战图：安全降级提示只出现一次")
    func aggregatesMultipleFocusesWithSingleSafetyNote() {
        let twoFocuses = LegalOutputCard.caseFacts(CaseFactsCard(title: "检索焦点", focuses: [
            CaseFactsFocus(id: "f1", label: "焦点甲", causeOfAction: "买卖合同纠纷", year: "2022", keywords: "货款"),
            CaseFactsFocus(id: "f2", label: "焦点乙", causeOfAction: "违约金调整", year: "2022", keywords: "违约金 过高"),
        ]))
        let out = CaseRetrievalReportPostProcessor.process(response(cards: [twoFocuses]))
        let reports = out.cards.filter { if case .caseRetrievalReport = $0 { return true }; return false }
        #expect(reports.count == 1)
        if case let .caseRetrievalReport(c) = reports.first {
            #expect(c.markdown.components(separatedBy: CaseRetrievalReport.safetyNote).count - 1 == 1)
            #expect(c.markdown.contains("焦点甲"))
            #expect(c.markdown.contains("焦点乙"))
        }
    }
}
