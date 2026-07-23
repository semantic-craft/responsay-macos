import Testing
import Foundation
@testable import ResponsayCore

/// 102 — LegalSkillCompiler + LegalSkillRegistry.
private func skillMD(
    id: String = "litigation.evidence-matrix",
    domain: String = "litigation",
    scene: String = "litigation",
    stages: String = #"["briefDrafting","evidenceReview"]"#,
    keywords: String = #"["事实与理由","证据"]"#,
    mandatory: String = #"["主张→要件→待证事实→证据"]"#,
    disclaimer: String = "本输出为辅助分析,不构成法律意见;事实与法条需核验。",
    cards: String = #"["evidenceArgumentMatrix","verificationTodos"]"#,
    interaction: String? = nil,
    includeBlock: Bool = true
) -> String {
    let interactionLine = interaction.map { #""interaction":"\#($0)","# } ?? ""
    let block = """
    ```legal-skill
    {
      "schemaVersion":"LEGAL_SKILL/v1","id":"\(id)","title":"证据论证矩阵","domain":"\(domain)","language":"zh",\(interactionLine)
      "triggers":{"keywords":\(keywords),"appHints":["Word"],"windowTitleHints":[],"minSelectedTextLength":0},
      "inputs":["selectedText","textBeforeCursor"],
      "sceneLayer":{"scene":"\(scene)","applicableStages":\(stages),"preconditions":[],"nextActionCandidates":[]},
      "reasoningKernel":{"mandatoryMapping":\(mandatory),"forbidden":["编造证据"]},
      "outputCards":\(cards),
      "risk":{"level":"high","disclaimer":"\(disclaimer)"}
    }
    ```
    """
    return """
    \(includeBlock ? block : "# 无元数据块")

    ## Skill Instructions
    把选区的事实与理由映射到证据。

    ## Reasoning Procedure
    主张 → 要件 → 待证事实 → 证据。

    ## Output Constraint
    只返回证据论证矩阵卡;新坐标标 [待核]。
    """
}

/// 122 — a `kind:rewrite` skill: prompt + examples, no reasoning kernel / output cards / risk.
private func rewriteSkillMD(
    id: String = "rewrite.litigation.adversarial",
    promptKey: String? = "把选中文本改写为对抗性诉讼文书语域，保持法律含义与事实不变。",
    examples: String = #"[{"input":"对方违约了","output":"被告之行为已构成根本违约"}]"#,
    instructionsBody: String = ""
) -> String {
    let promptLine = promptKey.map { "\"prompt\":\"\($0)\"," } ?? ""
    let block = """
    ```legal-skill
    {
      "schemaVersion":"LEGAL_SKILL/v1","id":"\(id)","title":"对抗性文书体","domain":"litigation","language":"zh",
      "kind":"rewrite",
      \(promptLine)
      "examples":\(examples),
      "sceneLayer":{"scene":"litigation","applicableStages":["briefDrafting"],"preconditions":[],"nextActionCandidates":[]}
    }
    ```
    """
    return """
    \(block)

    ## Skill Instructions
    \(instructionsBody)
    """
}

struct LegalSkillCompilerTests {
    private let compiler = LegalSkillCompiler()

    @Test func defaultKind_isGeneration() throws {
        // Existing corpus has no `kind` field → must default to generation (backward compat).
        #expect(try compiler.compile(skillMD()).metadata.kind == .generation)
    }

    @Test func defaultInteraction_isOneShot() throws {
        // Existing corpus has no `interaction` field → must default to oneShot (backward compat).
        #expect(try compiler.compile(skillMD()).metadata.interaction == .oneShot)
    }

    @Test func explicitInteraction_conversation_decodes() throws {
        // A skill that declares multi-turn must decode to .conversation (drives §3 routing).
        #expect(try compiler.compile(skillMD(interaction: "conversation")).metadata.interaction == .conversation)
    }

    @Test func unknownInteraction_throwsInvalid() {
        // PRESENT but unknown value = author error, not a silent default (matches kind/outputCards).
        #expect {
            try compiler.compile(skillMD(interaction: "chat"))
        } throws: { error in
            if case LegalSkillCompileError.invalidMetadataJSON = error { return true }
            return false
        }
    }

    @Test func rewriteKind_compiles_skippingGenerationGates() throws {
        // A rewrite skill omits reasoningKernel / risk — generation gates must not fire.
        let skill = try compiler.compile(rewriteSkillMD())
        #expect(skill.metadata.kind == .rewrite)
        #expect(skill.metadata.prompt?.contains("对抗性") == true)
        #expect(skill.metadata.examples.count == 1)
        #expect(skill.metadata.examples.first?.input == "对方违约了")
    }

    @Test func rewriteKind_promptFromInstructionsWhenKeyAbsent() throws {
        // Author may put the prompt in the `## Skill Instructions` section instead of `prompt`.
        let skill = try compiler.compile(rewriteSkillMD(promptKey: nil, instructionsBody: "改写为正式法律意见体。"))
        #expect(skill.metadata.kind == .rewrite)
        #expect(skill.skillInstructions.contains("正式法律意见体"))
    }

    @Test func rewriteKind_missingPrompt_throwsEmptyRewritePrompt() {
        // No `prompt` key AND empty Skill Instructions → nothing to drive the rewrite.
        #expect(throws: LegalSkillCompileError.emptyRewritePrompt) {
            try compiler.compile(rewriteSkillMD(promptKey: nil, instructionsBody: "   "))
        }
    }

    @Test func compilesValidSkill() throws {
        let skill = try compiler.compile(skillMD())
        #expect(skill.id == "litigation.evidence-matrix")
        #expect(skill.metadata.domain == .litigation)
        #expect(skill.metadata.outputCards.contains(.evidenceArgumentMatrix))
        #expect(skill.skillInstructions.contains("事实与理由"))
        #expect(skill.reasoningProcedure.contains("要件"))
        #expect(skill.outputConstraint.contains("待核"))
    }

    @Test func missingMetadataBlock_throws() {
        #expect(throws: LegalSkillCompileError.missingMetadataBlock) {
            try compiler.compile(skillMD(includeBlock: false))
        }
    }

    @Test func badJSON_throwsInvalid() {
        let md = "```legal-skill\n{ not valid json ,, }\n```\n## Skill Instructions\nx"
        #expect(throws: LegalSkillCompileError.self) { try compiler.compile(md) }
    }

    @Test func missingRequiredField_throwsInvalid() {
        // remove "title" → JSONDecoder fails the required key
        let md = skillMD().replacingOccurrences(of: #""title":"证据论证矩阵","#, with: "")
        #expect {
            try compiler.compile(md)
        } throws: { error in
            if case LegalSkillCompileError.invalidMetadataJSON = error { return true }
            return false
        }
    }

    @Test func unknownCardType_throwsInvalid() {
        let md = skillMD(cards: #"["bogusCard"]"#)
        #expect {
            try compiler.compile(md)
        } throws: { error in
            if case LegalSkillCompileError.invalidMetadataJSON = error { return true }
            return false
        }
    }

    @Test func emptyMandatoryMapping_throws() {
        #expect(throws: LegalSkillCompileError.emptyMandatoryMapping) {
            try compiler.compile(skillMD(mandatory: "[]"))
        }
    }

    @Test func emptyDisclaimer_throws() {
        #expect(throws: LegalSkillCompileError.emptyDisclaimer) {
            try compiler.compile(skillMD(disclaimer: ""))
        }
    }
}

struct LegalSkillRegistryTests {
    private let compiler = LegalSkillCompiler()

    private func registry() throws -> LegalSkillRegistry {
        let a = try compiler.compile(skillMD(id: "litigation.evidence-matrix"))
        let b = try compiler.compile(skillMD(
            id: "privacy.pia-triage", domain: "privacy", scene: "privacy",
            stages: #"["piaTriage"]"#, keywords: #"["个人信息","PIA"]"#))
        return try LegalSkillRegistry([a, b])
    }

    @Test func lookupBySceneAndStage() throws {
        let reg = try registry()
        let litigation = reg.candidates(scene: .litigation, stage: .briefDrafting)
        #expect(litigation.map(\.id) == ["litigation.evidence-matrix"])
        #expect(reg.candidates(scene: .litigation, stage: .piaTriage).isEmpty)  // stage not applicable
        #expect(reg.candidates(scene: .privacy).map(\.id) == ["privacy.pia-triage"])
    }

    @Test func lookupByKeyword() throws {
        let reg = try registry()
        #expect(reg.candidates(scene: .litigation, keywords: ["证据"]).count == 1)
        #expect(reg.candidates(scene: .litigation, keywords: ["无关词"]).isEmpty)
    }

    @Test func duplicateID_throws() throws {
        let a = try compiler.compile(skillMD(id: "dup"))
        let b = try compiler.compile(skillMD(id: "dup", domain: "privacy", scene: "privacy"))
        #expect(throws: LegalSkillRegistryError.duplicateID("dup")) {
            try LegalSkillRegistry([a, b])
        }
    }

    @Test func skillByID() throws {
        let reg = try registry()
        #expect(reg.skill(id: "privacy.pia-triage") != nil)
        #expect(reg.skill(id: "nope") == nil)
    }
}
