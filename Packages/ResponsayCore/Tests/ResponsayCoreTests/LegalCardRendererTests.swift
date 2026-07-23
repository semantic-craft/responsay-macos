import Testing
import Foundation
@testable import ResponsayCore

/// 107 — LegalCardRenderer: deterministic insert affordances + titles.
struct LegalCardRendererTests {
    private let renderer = LegalCardRenderer()

    private func response(_ cards: [LegalOutputCard], anchors: [VerificationAnchor] = []) -> LegalSkillResponse {
        LegalSkillResponse(runId: "r", skillId: "s", scene: .litigation, stage: .briefDrafting,
                           summary: "", cards: cards, verificationAnchors: anchors)
    }

    @Test func anchorA_matrixPlusTodos_offersOnlyTodoInsert() {
        let anchor = VerificationAnchor(id: "a1", label: "《民法典》第577条", kind: .law, query: "民法典 577")
        let r = response([
            .evidenceArgumentMatrix(EvidenceArgumentMatrixCard(title: "矩阵", rows: [])),
            .verificationTodos(VerificationTodosCard(title: "待核", anchorIds: ["a1"])),
        ], anchors: [anchor])
        let aff = renderer.affordances(for: r)
        #expect(aff.map(\.kind) == [.verificationTodos])      // matrix is reference-only
        #expect(aff.first?.text.contains("[待核] 《民法典》第577条") == true)
        #expect(aff.first?.containsPending == true)
    }

    @Test func anchorB_counterargumentPlusQuery_offersQueryInsert() {
        let r = response([
            .counterargument(CounterargumentCard(title: "反方", thesis: "t", implicitPremises: [], items: [])),
            .cnkiQuery(CNKIQueryCard(title: "检索式", expertQuery: "SU=('个人信息')")),
        ])
        let aff = renderer.affordances(for: r)
        #expect(aff.map(\.kind) == [.query])
        #expect(aff.first?.text == "SU=('个人信息')")
        #expect(aff.first?.containsPending == false)
    }

    @Test func insertableParagraph_offersBodyInsert_carryingPendingFlag() {
        let r = response([
            .insertableParagraph(InsertableParagraphCard(
                title: "段落", text: "本案中，被告……[待核]", containsPendingVerification: true)),
        ])
        let aff = renderer.affordances(for: r)
        #expect(aff.map(\.kind) == [.body])
        #expect(aff.first?.label == "插入正文")
        #expect(aff.first?.containsPending == true)
    }

    @Test func fallback_hasNoInsertAffordance_copyOnly() {
        let r = response([.fallbackText(FallbackTextCard(title: "降级", text: "raw text"))])
        #expect(renderer.affordances(for: r).isEmpty)          // insert disabled; view offers copy
    }

    @Test func titles_perCardType() {
        #expect(renderer.title(for: .cnkiQuery(CNKIQueryCard(title: "", expertQuery: ""))) == "CNKI 检索式")
        #expect(renderer.title(for: .fallbackText(FallbackTextCard(title: "", text: ""))) == "降级文本")
        #expect(renderer.title(for: .evidenceArgumentMatrix(EvidenceArgumentMatrixCard(title: "", rows: []))) == "证据论证矩阵")
    }
}
