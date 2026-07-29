import Testing
import Foundation
@testable import ResponsayCore

/// 416 — the pure classifier behind 设置›技能库 two top-level categories
/// (日常办公 / 法律技能). UI sections consume the same function, so the split is
/// pinned here rather than in a view: generation skills + anything tagged legal land
/// in 法律技能; general rewrite style packs land in 日常办公.
struct SkillCategorizerTests {

    private let compiler = LegalSkillCompiler()

    private func genMD(id: String) -> String {
        """
        ```legal-skill
        {
          "schemaVersion":"LEGAL_SKILL/v1","id":"\(id)","title":"生成技能","domain":"litigation","language":"zh",
          "triggers":{"keywords":["证据"],"appHints":[],"windowTitleHints":[],"minSelectedTextLength":0},
          "inputs":["selectedText"],
          "sceneLayer":{"scene":"litigation","applicableStages":["briefDrafting"],"preconditions":[],"nextActionCandidates":[]},
          "reasoningKernel":{"mandatoryMapping":["主张→证据"],"forbidden":[]},
          "outputCards":["evidenceArgumentMatrix"],
          "risk":{"level":"high","disclaimer":"辅助分析，需核验。"}
        }
        ```
        ## Skill Instructions
        x
        """
    }

    private func rewriteMD(id: String, tags: [String] = []) -> String {
        let tagsJSON = tags.map { "\"\($0)\"" }.joined(separator: ",")
        return """
        ```legal-skill
        {"schemaVersion":"LEGAL_SKILL/v1","id":"\(id)","title":"改写技能","domain":"litigation","language":"zh","kind":"rewrite","prompt":"改写。","examples":[],"tags":[\(tagsJSON)]}
        ```
        ## Skill Instructions
        """
    }

    @Test func generationSkill_isLegal() throws {
        let skill = try compiler.compile(genMD(id: "litigation.gen_a"))
        #expect(SkillCategorizer.category(for: skill) == .legal)
    }

    @Test func rewriteSkill_isEverydayOffice() throws {
        let skill = try compiler.compile(rewriteMD(id: "rewrite.office_a"))
        #expect(SkillCategorizer.category(for: skill) == .everydayOffice)
    }

    @Test func rewriteSkillTaggedLegal_staysLegal() throws {
        let skill = try compiler.compile(rewriteMD(id: "rewrite.legal_doc", tags: ["法律"]))
        #expect(SkillCategorizer.category(for: skill) == .legal)
    }

    @Test func legalTagMatchIsCaseInsensitive() {
        #expect(SkillCategorizer.category(kind: .rewrite, tags: ["Legal"]) == .legal)
        #expect(SkillCategorizer.category(kind: .rewrite, tags: ["公文"]) == .everydayOffice)
    }

    /// 日常办公 = the selectable flavor packs across both lanes: 强制清单 / 正式表达 (听写) and
    /// 精简压缩 (写作). The two 改写力度 档 backings (轻度润色 / 表达升级) route to
    /// .rewriteTierDefault — see the next test — so they stay OUT of this selectable list.
    /// A flavor pack mis-tagged into 法律技能 also breaks this.
    @Test func bundledEverydayOfficeSkillsAreExactlyTheFlavorPacks() throws {
        let bundled = try LegalSkillRegistry.loadBundled().skills
        let everyday = bundled
            .filter { SkillCategorizer.category(for: $0) == .everydayOffice }
            .map(\.id).sorted()
        #expect(everyday == [
            "style.clear_structure.cn",
            "style.condense.cn",
            "style.formal_expression.cn",
        ])
    }

    /// (2026-06-16) — 轻度润色 and 表达升级 each back a 改写力度 档 directly, so neither is a 日常办公
    /// selectable: both categorize as .rewriteTierDefault.
    @Test func tierBackingSkills_areRewriteTierDefault_notEverydayOffice() throws {
        let bundled = try LegalSkillRegistry.loadBundled().skills
        for id in [SkillCategorizer.expressionUpgradeSkillID, SkillCategorizer.lightPolishSkillID] {
            let skill = try #require(bundled.first { $0.id == id })
            #expect(SkillCategorizer.category(for: skill) == .rewriteTierDefault)
        }
    }
}
