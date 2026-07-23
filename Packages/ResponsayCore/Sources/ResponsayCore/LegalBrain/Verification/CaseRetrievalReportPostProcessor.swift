import Foundation

// MARK: - 487 检索作战图 post-processor
//
// The LLM extracts 争议焦点 + 案情字段 (`caseFacts` card); query/URL construction stays
// deterministic app-side so no judgment URL is ever hallucinated. This processor turns the
// model's `caseFacts` card(s) into ONE deterministic `caseRetrievalReport` 作战图 card
// (`CaseRetrievalReport` / `CaseRetrievalPlanner`, #246/#474) and drops the raw facts card.
// A response with no `caseFacts` card is returned unchanged.

public enum CaseRetrievalReportPostProcessor {
    public static func process(_ response: LegalSkillResponse) -> LegalSkillResponse {
        let focuses = response.cards.flatMap { card -> [CaseFactsFocus] in
            if case let .caseFacts(c) = card { return c.focuses }
            return []
        }
        guard !focuses.isEmpty else { return response }

        let markdown = CaseRetrievalReport.build(focuses: focuses.map { ($0.label, $0.facts) })
        let reportCard = LegalOutputCard.caseRetrievalReport(
            CaseRetrievalReportCard(title: "检索作战图", markdown: markdown))
        let kept = response.cards.filter { if case .caseFacts = $0 { return false }; return true }

        return LegalSkillResponse(
            schemaVersion: response.schemaVersion, runId: response.runId, skillId: response.skillId,
            scene: response.scene, stage: response.stage, summary: response.summary,
            cards: kept + [reportCard], insertables: response.insertables,
            verificationAnchors: response.verificationAnchors, warnings: response.warnings)
    }
}
