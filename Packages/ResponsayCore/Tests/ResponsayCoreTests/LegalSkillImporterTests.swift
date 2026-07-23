import Testing
import Foundation
@testable import ResponsayCore

/// 122 — LegalSkillImporter: compile an imported `*.LEGAL_SKILL.md`, route by `kind`
/// (rewrite → StylePack, generation → LegalSkillCompiled), persist via an injected store,
/// and fail cleanly on bad content. Imported skills are NOT auto-enabled.
struct LegalSkillImporterTests {

    private func rewriteMD(id: String = "rewrite.litigation.adversarial") -> String {
        """
        ```legal-skill
        {
          "schemaVersion":"LEGAL_SKILL/v1","id":"\(id)","title":"对抗性文书体","domain":"litigation","language":"zh",
          "kind":"rewrite",
          "prompt":"把选中文本改写为对抗性诉讼文书语域，保持法律含义与事实不变。",
          "examples":[{"input":"对方违约了","output":"被告之行为已构成根本违约"}],
          "sceneLayer":{"scene":"litigation","applicableStages":["briefDrafting"],"preconditions":[],"nextActionCandidates":[]}
        }
        ```

        ## Skill Instructions
        """
    }

    private func generationMD(id: String = "litigation.imported_gen") -> String {
        """
        ```legal-skill
        {
          "schemaVersion":"LEGAL_SKILL/v1","id":"\(id)","title":"导入的生成技能","domain":"litigation","language":"zh",
          "triggers":{"keywords":["证据"],"appHints":["Word"],"windowTitleHints":[],"minSelectedTextLength":0},
          "inputs":["selectedText"],
          "sceneLayer":{"scene":"litigation","applicableStages":["briefDrafting"],"preconditions":[],"nextActionCandidates":[]},
          "reasoningKernel":{"mandatoryMapping":["主张→要件→证据"],"forbidden":["编造证据"]},
          "outputCards":["evidenceArgumentMatrix"],
          "risk":{"level":"high","disclaimer":"辅助分析，非法律意见；事实/法条需核验。"}
        }
        ```

        ## Skill Instructions
        梳理证据。
        """
    }

    @Test func rewriteContent_producesRewriteStylePack() {
        let outcome = LegalSkillImporter().importSkill(markdown: rewriteMD())
        guard case let .rewrite(pack) = outcome else { Issue.record("expected .rewrite, got \(outcome)"); return }
        #expect(pack.origin == .localImport)
        #expect(pack.examples.count == 1)
        #expect(pack.scope.scenes == [.litigation])
        #expect(pack.scope.stages == [.briefDrafting])
        #expect(pack.systemPrompt.contains("对抗性"))
    }

    @Test func generationContent_producesGenerationOutcome() {
        let outcome = LegalSkillImporter().importSkill(markdown: generationMD())
        guard case let .generation(compiled) = outcome else { Issue.record("expected .generation, got \(outcome)"); return }
        #expect(compiled.metadata.kind == .generation)
        #expect(compiled.id == "litigation.imported_gen")
    }

    @Test func badContent_producesFailed() {
        let outcome = LegalSkillImporter().importSkill(markdown: "没有元数据块的随便一段文字")
        guard case let .failed(err) = outcome else { Issue.record("expected .failed, got \(outcome)"); return }
        #expect(err == .missingMetadataBlock)
    }

    @Test func rewriteMissingPrompt_producesFailed() {
        let md = """
        ```legal-skill
        {"schemaVersion":"LEGAL_SKILL/v1","id":"x.y","title":"空","domain":"litigation","language":"zh","kind":"rewrite","examples":[]}
        ```

        ## Skill Instructions
        """
        guard case let .failed(err) = LegalSkillImporter().importSkill(markdown: md) else {
            Issue.record("expected .failed"); return
        }
        #expect(err == .emptyRewritePrompt)
    }

    @Test func import_persistsToInjectedStore() throws {
        let store = InMemoryImportedLegalSkillStore()
        _ = LegalSkillImporter(store: store).importSkill(markdown: rewriteMD())
        #expect(try store.loadAllRawMarkdown().count == 1)
        #expect(try store.loadAllRawMarkdown().first?.contains("对抗性") == true)
    }

    @Test func importedSkill_isDisabledByDefault() {
        // The enabled-set only seeds the 5 built-ins; an imported id is off until the user enables it.
        #expect(!EnabledLegalSkillStore.defaultEnabledIDs.contains("rewrite.litigation.adversarial"))
    }
}

/// Test double for the import storage seam.
private final class InMemoryImportedLegalSkillStore: ImportedLegalSkillStore {
    private var saved: [String] = []
    func save(rawMarkdown: String, id: String) throws { saved.append(rawMarkdown) }
    func loadAllRawMarkdown() throws -> [String] { saved }
}
