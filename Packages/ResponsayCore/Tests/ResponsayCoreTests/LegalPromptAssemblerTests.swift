import Testing
import Foundation
@testable import ResponsayCore

/// 106 — LegalPromptAssembler: injects the skill kernel + the non-negotiable [待核] constraint.
struct LegalPromptAssemblerTests {
    private let assembler = LegalPromptAssembler()

    private func anchorSkill() throws -> LegalSkillCompiled {
        let reg = try LegalSkillRegistry.loadBundled()
        return try #require(reg.skill(id: "verification.fact_check.cn"))
    }

    @Test func assemble_injectsKernelAndVerificationConstraint() throws {
        let skill = try anchorSkill()
        let context = LegalContextPayload(
            selectedText: "被告拖欠货款，构成违约。", nearbyHeading: "事实与理由",
            scene: .litigation, stage: .briefDrafting, appName: "Microsoft Word")
        let prompt = assembler.assemble(skill: skill, context: context)

        #expect(prompt.system.contains("引注源验"))              // skill title
        #expect(prompt.system.contains("核心查验目标"))          // mandatoryMapping
        #expect(prompt.system.contains("无法确认"))              // [待核] hard constraint
        #expect(prompt.system.contains("LEGAL_OUTPUT/v1"))       // strict-JSON instruction
        #expect(prompt.user.contains("被告拖欠货款"))            // selected text
        #expect(prompt.user.contains("litigation"))             // scene
        #expect(prompt.user.contains("事实与理由"))              // nearby heading
    }

    @Test func assemble_includesProfileSubsetWhenProvided() throws {
        let skill = try anchorSkill()
        let profile = LegalPracticeProfile(
            id: "p1", role: .practitioner, jurisdictions: ["CN", "Guangdong"],
            createdAt: "2026-06-07", updatedAt: "2026-06-07")
        let context = LegalContextPayload(
            selectedText: "x", scene: .litigation, stage: .briefDrafting, appName: "Word")
        let prompt = assembler.assemble(skill: skill, context: context, profile: profile)
        #expect(prompt.user.contains("practitioner"))
        #expect(prompt.user.contains("CN/Guangdong"))
    }

    @Test func assemble_neverLeaksRedLinesOrEscalation() throws {
        // 109 minimal-subset boundary: sensitive profile fields must never reach the prompt.
        let skill = try anchorSkill()
        let profile = LegalPracticeProfile(
            id: "p", role: .practitioner, primaryDomains: [.privacy], jurisdictions: ["CN"],
            writingModes: [.productReview], citationPreference: .firmMemo, sourcePriority: [.govLaw],
            redLines: ["不得涉及客户秘密ABC"],
            escalationMatrix: [EscalationRule(id: "e", condition: "涉及出境XYZ", action: "本地模型")],
            modelPreference: .localFirst, privacyPreference: .selectedTextOnly,
            createdAt: "t", updatedAt: "t")
        let context = LegalContextPayload(
            selectedText: "x", scene: .privacy, stage: .piaTriage, appName: "Word")
        let prompt = assembler.assemble(skill: skill, context: context, profile: profile)
        let whole = prompt.system + "\n" + prompt.user
        #expect(whole.contains("不得涉及客户秘密ABC") == false)   // redLine not injected
        #expect(whole.contains("涉及出境XYZ") == false)           // escalation not injected
    }

    @Test func assemble_includesExactOutputSchema() throws {
        // Without the schema the model invents an internally-tagged / wrong-field shape (live finding).
        let skill = try anchorSkill()   // 引注源验 emits verificationTodos
        let context = LegalContextPayload(
            selectedText: "x", scene: .litigation, stage: .briefDrafting, appName: "Word")
        let prompt = assembler.assemble(skill: skill, context: context)
        #expect(prompt.system.contains("\"verificationTodos\""))   // externally-tagged card shape
        #expect(prompt.system.contains("外标记"))
        #expect(prompt.system.contains("insertables"))                   // top-level required fields spelled out
        #expect(prompt.system.contains("\"label\""))                     // anchor uses label/kind/query, not content
    }

    @Test func outputSchema_dedupesFallbackForConceptAndRisk() {
        let schema = LegalPromptAssembler.outputSchema(for: [.conceptMap, .riskMatrix, .verificationTodos])
        let fallbackLines = schema.components(separatedBy: #"{"fallbackText""#).count - 1
        #expect(fallbackLines == 1)   // conceptMap + riskMatrix both → fallbackText, deduped
    }

    @Test func repairPrompt_asksToFixJSONOnly_andCarriesOutputSchema() {
        // Live finding (qwen3.7-plus): without the schema the repair pass cannot fix
        // structural errors like insertableParagraph content misplaced into `insertables`.
        let prompt = assembler.repairPrompt(
            brokenOutput: "{ not json ,, }", outputCards: [.strategyRecommendation, .insertableParagraph])
        #expect(prompt.system.contains("只修复"))
        #expect(prompt.system.contains("[待核]"))
        #expect(prompt.system.contains("\"insertableParagraph\""))   // card shapes included
        #expect(prompt.system.contains("顶层 insertables 恒为空数组"))
        #expect(prompt.user == "{ not json ,, }")
    }

    // 191 — active matter context is injected for case-consistency; off-path stays byte-identical.
    @Test func assemble_includesMatterContextWhenActive() throws {
        let skill = try anchorSkill()
        let context = LegalContextPayload(
            selectedText: "对方主张违约", scene: .litigation, stage: .briefDrafting, appName: "Word")
        let matter = Matter(
            slug: "acme-2026", title: "Acme 买卖合同纠纷", scene: .litigation, client: "我方公司",
            counterparties: ["Acme 公司"], role: "被告",
            elementChecklist: ["合同有效成立", "违约行为"], evidenceList: ["合同原件"],
            overrides: ["客户要求关系保全语气"], createdAt: "t", updatedAt: "t")
        let prompt = assembler.assemble(skill: skill, context: context, matter: matter)
        #expect(prompt.user.contains("本案上下文"))
        #expect(prompt.user.contains("Acme 买卖合同纠纷"))
        #expect(prompt.user.contains("已建要件表：合同有效成立；违约行为"))
        #expect(prompt.user.contains("客户要求关系保全语气"))
    }

    @Test func assemble_offPathByteIdentical_whenNoMatter() throws {
        let skill = try anchorSkill()
        let context = LegalContextPayload(
            selectedText: "x", scene: .litigation, stage: .briefDrafting, appName: "Word")
        let withoutParam = assembler.assemble(skill: skill, context: context)
        let withNil = assembler.assemble(skill: skill, context: context, matter: nil)
        #expect(withoutParam == withNil)                          // the new param changes nothing when nil
        #expect(withoutParam.user.contains("本案上下文") == false)
    }
}
