import Testing
import Foundation
@testable import ResponsayCore

/// 104 — LegalSceneStageRouter. Drives the full deterministic chain end-to-end:
/// `ExpressionContext` → `ContextSignalLayer.assemble` (113–116) → bundle →
/// router → `ContextConfidenceScorer` (117) → tier + candidate cards (102).
struct LegalSceneStageRouterTests {
    private let layer = ContextSignalLayer()
    private let router = LegalSceneStageRouter()
    private let now = Date(timeIntervalSince1970: 0)   // injected for determinism

    // MARK: - Fixtures

    private func litigationSkillMD() -> String {
        """
        ```legal-skill
        {
          "schemaVersion":"LEGAL_SKILL/v1","id":"litigation.evidence-matrix","title":"证据论证矩阵",
          "domain":"litigation","language":"zh",
          "triggers":{"keywords":["事实与理由","证据"],"appHints":["Word"],"windowTitleHints":[],"minSelectedTextLength":0},
          "inputs":["selectedText","textBeforeCursor"],
          "sceneLayer":{"scene":"litigation","applicableStages":["briefDrafting","evidenceReview"],"preconditions":[],"nextActionCandidates":[]},
          "reasoningKernel":{"mandatoryMapping":["主张→要件→待证事实→证据"],"forbidden":["编造证据"]},
          "outputCards":["evidenceArgumentMatrix","verificationTodos"],
          "risk":{"level":"high","disclaimer":"本输出为辅助分析,不构成法律意见;事实与法条需核验。"}
        }
        ```

        ## Skill Instructions
        把选区的事实与理由映射到证据。
        ## Reasoning Procedure
        主张 → 要件 → 待证事实 → 证据。
        ## Output Constraint
        只返回证据论证矩阵卡;新坐标标 [待核]。
        """
    }

    private func academicSkillMD() -> String {
        """
        ```legal-skill
        {
          "schemaVersion":"LEGAL_SKILL/v1","id":"academic.citation-draft","title":"引注草稿",
          "domain":"academicWriting","language":"zh",
          "triggers":{"keywords":["参考文献","综述"],"appHints":["Pages"],"windowTitleHints":[],"minSelectedTextLength":0},
          "inputs":["selectedText"],
          "sceneLayer":{"scene":"academicWriting","applicableStages":["citationDrafting","literatureReview"],"preconditions":[],"nextActionCandidates":[]},
          "reasoningKernel":{"mandatoryMapping":["论点→出处→引注格式"],"forbidden":["编造出处"]},
          "outputCards":["cnkiQuery","verificationTodos"],
          "risk":{"level":"medium","disclaimer":"引注需核验;新坐标标 [待核]。"}
        }
        ```

        ## Skill Instructions
        为选区生成引注草稿。
        ## Reasoning Procedure
        论点 → 出处 → 引注格式。
        ## Output Constraint
        新坐标标 [待核]。
        """
    }

    private func registry() throws -> LegalSkillRegistry {
        let compiler = LegalSkillCompiler()
        return try LegalSkillRegistry([
            try compiler.compile(litigationSkillMD()),
            try compiler.compile(academicSkillMD()),
        ])
    }

    private func emptyRegistry() throws -> LegalSkillRegistry { try LegalSkillRegistry([]) }

    private func bundle(_ context: ExpressionContext, browserURL: String? = nil) -> ContextSignalBundle {
        layer.assemble(context: context, browserURL: browserURL, now: now)
    }

    // MARK: - Anchor A: litigation / briefDrafting → auto

    @Test func anchorA_litigationBriefDrafting_autoCandidates() throws {
        let ctx = ExpressionContext(
            appName: "Microsoft Word",
            bundleIdentifier: "com.microsoft.word",
            windowTitle: "起诉状.docx",
            selectedText: "被告拖欠货款,构成违约,应承担违约责任。",
            textBeforeCursor: "一、事实与理由\n原告与被告签订买卖合同……"
        )
        let decision = router.route(bundle(ctx), registry: try registry())

        #expect(decision.tier == "auto")
        #expect(decision.classification.scene == .litigation)
        #expect(decision.classification.stage == .briefDrafting)
        #expect(decision.classification.confidence >= 0.65)
        #expect(decision.cards.map(\.skillId) == ["litigation.evidence-matrix"])
        #expect(decision.cards.first?.badges.contains("高风险") == true)
        #expect(decision.cards.first?.badges.contains("待核") == true)
    }

    // MARK: - Anchor B: academicWriting → auto

    @Test func anchorB_academicWriting_auto() throws {
        let ctx = ExpressionContext(
            appName: "Pages",
            bundleIdentifier: "com.apple.pages",
            windowTitle: "论文初稿",
            selectedText: "本文综述了个人信息处理者的合规义务。",
            textBeforeCursor: "参考文献\n[1] ……"
        )
        let decision = router.route(bundle(ctx), registry: try registry())

        #expect(decision.classification.scene == .academicWriting)
        #expect(decision.classification.confidence >= 0.65)
        #expect(decision.tier == "auto")
        #expect(decision.cards.map(\.skillId) == ["academic.citation-draft"])
    }

    // MARK: - Ambiguous: no usable signal → generic, asks user

    @Test func ambiguous_noSignal_genericAndAsksUser() throws {
        let ctx = ExpressionContext(
            appName: "Google Chrome",
            bundleIdentifier: "com.google.chrome",
            windowTitle: "New Tab",
            selectedText: "Some neutral selected sentence."
        )
        let decision = router.route(bundle(ctx), registry: try registry())

        #expect(decision.tier == "generic")
        #expect(decision.classification.shouldAskUser == true)
        #expect(decision.classification.scene == .unknown)
        #expect(decision.cards.map(\.skillId) == [
            "generic.elementAnalysis", "generic.factVerification",
            "generic.searchQuery", "generic.counterargument",
        ])
    }

    // MARK: - Mid confidence → confirm card

    @Test func midConfidence_confirmScene() throws {
        // Word with no heading cue: litigation prior dominates but lead is modest →
        // confidence lands in the 0.45–0.65 confirm band.
        let ctx = ExpressionContext(
            appName: "Microsoft Word",
            bundleIdentifier: "com.microsoft.word",
            windowTitle: "未命名文档",
            selectedText: "这段话需要润色一下。"
        )
        let decision = router.route(bundle(ctx), registry: try registry())

        #expect(decision.tier == "confirm")
        #expect(decision.classification.scene == .litigation)
        #expect(decision.classification.confidence >= 0.45)
        #expect(decision.classification.confidence < 0.65)
        #expect(decision.cards.contains { $0.skillId == "litigation.evidence-matrix" })
    }

    // MARK: - No selection → needsSelection

    @Test func noSelection_needsSelection() throws {
        let ctx = ExpressionContext(appName: "Microsoft Word", bundleIdentifier: "com.microsoft.word")
        let decision = router.route(bundle(ctx), registry: try registry())

        #expect(decision.tier == "needsSelection")
        #expect(decision.cards.isEmpty)
        #expect(decision.classification.shouldAskUser == true)
    }

    // MARK: - Confident scene but no authored skill → downgrade to generic

    @Test func confidentSceneNoSkill_downgradesToGeneric() throws {
        let ctx = ExpressionContext(
            appName: "Microsoft Word",
            bundleIdentifier: "com.microsoft.word",
            windowTitle: "起诉状.docx",
            selectedText: "被告拖欠货款,构成违约。",
            textBeforeCursor: "一、事实与理由\n……"
        )
        let decision = router.route(bundle(ctx), registry: try emptyRegistry())

        #expect(decision.tier == "generic")
        #expect(decision.classification.scene == .litigation)      // scene still recognized
        #expect(decision.cards.count == 4)
        #expect(decision.classification.reasons.contains { $0.contains("暂无内置技能") })
    }
}
