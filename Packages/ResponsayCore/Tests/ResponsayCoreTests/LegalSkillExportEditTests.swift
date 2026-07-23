import Testing
import Foundation
@testable import ResponsayCore

/// Phase 1 本地创作闭环 (legal-skill platform): the seams behind the LegalSkillsScreen 导出/编辑
/// actions — the shared export filename and the store delete that keeps an id-changing edit from
/// orphaning the old file. The UI (NSSavePanel / TextEditor sheet) is HITL.
struct LegalSkillExportEditTests {
    @Test func fileNameSanitizesIdAndAddsSuffix() {
        #expect(LegalSkillCompiled.fileName(forID: "practice.claim_and_defense.cn")
            == "practice.claim_and_defense.cn.LEGAL_SKILL.md")
        // Slashes and spaces become underscores so the id is a safe filename.
        #expect(LegalSkillCompiled.fileName(forID: "a/b c.cn") == "a_b_c.cn.LEGAL_SKILL.md")
    }

    @Test func storeDeleteRemovesFileAndIsNoOpWhenAbsent() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("respo-legalskill-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileImportedLegalSkillStore(directory: dir)

        try store.save(rawMarkdown: "x", id: "demo.skill.cn")
        #expect(try store.loadAllRawMarkdown().count == 1)

        try store.delete(id: "demo.skill.cn")
        #expect(try store.loadAllRawMarkdown().isEmpty)

        // No-op (no throw) when the file is already gone.
        try store.delete(id: "demo.skill.cn")
    }

    /// An edit that changes the skill id: persist under the new id, drop the old file — so the
    /// list shows one (the new) skill, not a stale duplicate.
    @Test func editChangingIdLeavesOnlyTheNewFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("respo-legalskill-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileImportedLegalSkillStore(directory: dir)

        try store.save(rawMarkdown: "old-body", id: "x.old.cn")
        try store.save(rawMarkdown: "new-body", id: "x.new.cn")
        try store.delete(id: "x.old.cn")

        #expect(try store.loadAllRawMarkdown() == ["new-body"])
    }
}
