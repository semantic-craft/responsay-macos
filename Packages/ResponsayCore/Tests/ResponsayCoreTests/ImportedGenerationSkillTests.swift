import Testing
import Foundation
@testable import ResponsayCore

/// 235 — imported generation skills merge into the bundled LegalSkillRegistry (user dir +
/// bundled corpus), appear in ⌥L candidates once enabled, and stay [待核]-disciplined.
/// Imported rewrite skills do NOT enter the legal registry (they are StylePacks).
struct ImportedGenerationSkillTests {

    private let compiler = LegalSkillCompiler()

    private func genMD(id: String) -> String {
        """
        ```legal-skill
        {
          "schemaVersion":"LEGAL_SKILL/v1","id":"\(id)","title":"导入生成技能","domain":"litigation","language":"zh",
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

    private func rewriteMD(id: String) -> String {
        """
        ```legal-skill
        {"schemaVersion":"LEGAL_SKILL/v1","id":"\(id)","title":"导入改写","domain":"litigation","language":"zh","kind":"rewrite","prompt":"改写为对抗体。","examples":[]}
        ```
        ## Skill Instructions
        """
    }

    @Test func merging_addsImportedGenerationSkill() throws {
        let base = try LegalSkillRegistry.loadBundled()
        let imported = try compiler.compile(genMD(id: "litigation.user_imported_gen"))
        let merged = try base.merging([imported])
        #expect(merged.skill(id: "litigation.user_imported_gen") != nil)
        #expect(merged.skills.count == base.skills.count + 1)
    }

    @Test func merging_duplicateID_throws() throws {
        let base = try LegalSkillRegistry.loadBundled()
        let dup = try compiler.compile(genMD(id: "verification.fact_check.cn")) // collides with bundled
        #expect(throws: LegalSkillRegistryError.duplicateID("verification.fact_check.cn")) {
            _ = try base.merging([dup])
        }
    }

    @Test func runtimeFactory_includesImportedGeneration_excludesRewrite() throws {
        let store = TwoSkillStore(rawMarkdowns: [
            genMD(id: "litigation.imported_gen_x"),
            rewriteMD(id: "rewrite.imported_y"),
        ])
        let runtime = try LegalSkillRuntime.bundled(executor: nil, importedStore: store)
        #expect(runtime.registry.skill(id: "litigation.imported_gen_x") != nil)   // generation merged
        #expect(runtime.registry.skill(id: "rewrite.imported_y") == nil)          // rewrite excluded
    }

    // 猎虫⑤ P1-1 — 撞内置 id 的导入文件曾是持久化毒丸：merging throw →
    // CaptureController 的 try? 吞掉 → runtime=nil → 整个 ⌥L 面板带着误导文案死亡，
    // 且文件无 UI 删除口。现 bundled-wins：坏文件被丢弃，其余照常。
    @Test func runtimeFactory_duplicateOnDisk_dropsImportKeepsBundledAlive() throws {
        let store = TwoSkillStore(rawMarkdowns: [
            genMD(id: "verification.fact_check.cn"),   // collides with bundled
            genMD(id: "litigation.survivor_x"),
        ])
        let runtime = try LegalSkillRuntime.bundled(executor: nil, importedStore: store)
        #expect(runtime.registry.skill(id: "verification.fact_check.cn") != nil)   // bundled alive
        #expect(runtime.registry.skill(id: "litigation.survivor_x") != nil)       // sibling unaffected
        #expect(!runtime.importedSkillIDs.contains("verification.fact_check.cn"))
    }

    @Test func importer_rejectsBundledCollidingID() {
        let importer = LegalSkillImporter(store: nil)
        let outcome = importer.importSkill(markdown: genMD(id: "verification.fact_check.cn"))
        guard case let .failed(error) = outcome else {
            Issue.record("expected duplicate-id rejection"); return
        }
        #expect(error == .duplicateSkillID("verification.fact_check.cn"))
    }

    // 猎虫⑤ P2-1 — kind 笔误（"rewite"）曾静默坍缩成 generation，作者收到
    // 「生成技能缺少推理内核」的误导报错；现在未知 kind 直接报 JSON 错误。
    @Test func compiler_unknownKindFailsLoudly() {
        let md = """
        ```legal-skill
        {"schemaVersion":"LEGAL_SKILL/v1","id":"typo.cn","title":"t","domain":"litigation","language":"zh","kind":"rewite","prompt":"x","examples":[]}
        ```
        """
        do {
            _ = try compiler.compile(md)
            Issue.record("expected unknown-kind failure")
        } catch let error as LegalSkillCompileError {
            // Must be the JSON-decode failure naming the unknown kind — the
            // pre-fix collapse produced .emptyMandatoryMapping instead (the
            // generation gate), which is why a bare `throws:` check pinned
            // nothing (fix-verifier finding).
            guard case let .invalidMetadataJSON(detail) = error else {
                Issue.record("wrong error: \(error)"); return
            }
            #expect(detail.contains("unknown legal-skill kind"))
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test func importedGenerationCard_carriesUnvettedBadge() throws {
        // 236: an imported skill's palette card is marked 第三方·未审; bundled skills are not.
        let store = TwoSkillStore(rawMarkdowns: [genMD(id: "litigation.unvetted_x")])
        let runtime = try LegalSkillRuntime.bundled(executor: nil, importedStore: store)
        let enabled = EnabledLegalSkillStore.defaultEnabledIDs.union(["litigation.unvetted_x"])
        let cards = runtime.suggestSkills(scene: .litigation, stage: .briefDrafting, enabled: enabled)
        let imported = cards.first { $0.skillId == "litigation.unvetted_x" }
        #expect(imported?.badges.contains(LegalSkillRuntime.unvettedBadge) == true)
        let bundled = cards.first { $0.skillId == "verification.fact_check.cn" }
        #expect(bundled?.badges.contains(LegalSkillRuntime.unvettedBadge) == false)
    }

    @Test func importedGeneration_hiddenUntilEnabled() throws {
        let store = TwoSkillStore(rawMarkdowns: [genMD(id: "litigation.imported_gen_z")])
        let runtime = try LegalSkillRuntime.bundled(executor: nil, importedStore: store)
        // default enabled-set has only the 5 built-ins → imported skill absent from candidates
        let cards = runtime.suggestSkills(
            scene: .litigation, stage: .briefDrafting,
            enabled: EnabledLegalSkillStore.defaultEnabledIDs)
        #expect(!cards.contains { $0.skillId == "litigation.imported_gen_z" })
        // once enabled, it appears
        let enabled = EnabledLegalSkillStore.defaultEnabledIDs.union(["litigation.imported_gen_z"])
        let cards2 = runtime.suggestSkills(scene: .litigation, stage: .briefDrafting, enabled: enabled)
        #expect(cards2.contains { $0.skillId == "litigation.imported_gen_z" })
    }
}

private struct TwoSkillStore: ImportedLegalSkillStore {
    let rawMarkdowns: [String]
    func save(rawMarkdown: String, id: String) throws {}
    func loadAllRawMarkdown() throws -> [String] { rawMarkdowns }
}
