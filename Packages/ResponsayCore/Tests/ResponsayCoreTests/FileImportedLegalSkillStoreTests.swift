import Testing
import Foundation
@testable import ResponsayCore

/// 122 — FileImportedLegalSkillStore: persist imported skills as `*.LEGAL_SKILL.md`
/// files in the user skill directory (separate from the read-only bundled corpus).
struct FileImportedLegalSkillStoreTests {

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("responsay-skilltest-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func saveThenLoad_roundTrips() throws {
        let dir = tempDir()
        let store = FileImportedLegalSkillStore(directory: dir)
        try store.save(rawMarkdown: "# hello\ncontent A", id: "a.b.cn")
        let all = try store.loadAllRawMarkdown()
        #expect(all == ["# hello\ncontent A"])
    }

    @Test func save_writesLegalSkillMdFile() throws {
        let dir = tempDir()
        try FileImportedLegalSkillStore(directory: dir).save(rawMarkdown: "x", id: "litigation.foo.cn")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        #expect(files.contains { $0.hasSuffix(".LEGAL_SKILL.md") })
    }

    @Test func loadAll_ignoresNonSkillFiles() throws {
        let dir = tempDir()
        let store = FileImportedLegalSkillStore(directory: dir)
        try store.save(rawMarkdown: "skill", id: "a.cn")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "junk".write(to: dir.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        #expect(try store.loadAllRawMarkdown() == ["skill"])
    }

    // 猎虫⑤ P1-2 — 目录里一个非 UTF-8 文件曾让整个 load throw，调用方 try? 吞掉后
    // 所有已导入技能集体静默蒸发。现逐文件跳过：坏文件不连坐。
    @Test func loadAll_skipsUnreadableFileKeepsOthers() throws {
        let dir = tempDir()
        let store = FileImportedLegalSkillStore(directory: dir)
        try store.save(rawMarkdown: "good skill", id: "good.cn")
        let badBytes = Data([0xFF, 0xFE, 0xC0, 0xC1])   // not valid UTF-8
        try badBytes.write(to: dir.appendingPathComponent("bad.LEGAL_SKILL.md"))
        #expect(try store.loadAllRawMarkdown() == ["good skill"])
    }

    @Test func loadAll_onMissingDirectory_isEmpty() throws {
        let store = FileImportedLegalSkillStore(directory: tempDir())
        #expect(try store.loadAllRawMarkdown().isEmpty)
    }
}
