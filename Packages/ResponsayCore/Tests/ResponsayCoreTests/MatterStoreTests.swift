import Testing
import Foundation
@testable import ResponsayCore

/// 188 — Matter store + lifecycle (folder-backed, default-off).
struct MatterStoreTests {
    private func tempStore() -> (MatterStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("matters")
        return (MatterStore(root: root), root)
    }

    private func sample(_ slug: String = "acme-2026") -> Matter {
        Matter(
            slug: slug, title: "Acme 买卖合同纠纷", scene: .litigation, client: "我方公司",
            counterparties: ["Acme 公司"], role: "被告",
            keyFacts: "对方主张违约：限7日内履行，否则起诉。",
            createdAt: "2026-06-08T00:00:00Z", updatedAt: "2026-06-08T00:00:00Z")
    }

    @Test func defaultOff_noActiveMatter() {
        let (store, _) = tempStore()
        #expect(store.isEnabled == false)
        #expect(store.activeMatter() == nil)
        #expect(store.list().isEmpty)
    }

    @Test func create_persists_optsIn_butDoesNotAutoSwitch() throws {
        let (store, root) = tempStore()
        try store.create(sample())
        #expect(store.isEnabled == true)            // opted in by creating
        #expect(store.activeMatter() == nil)        // but not auto-switched
        #expect(store.list().map(\.slug) == ["acme-2026"])
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: root.appendingPathComponent("acme-2026/matter.json").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent("acme-2026/matter.md").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent("acme-2026/history.md").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent("_log.yaml").path))
    }

    @Test func switch_thenActiveMatterLoads() throws {
        let (store, _) = tempStore()
        try store.create(sample())
        try store.switchActive(to: "acme-2026")
        let active = try #require(store.activeMatter())
        #expect(active.slug == "acme-2026")
        #expect(active.title == "Acme 买卖合同纠纷")
    }

    @Test func roundTrip_preservesChineseAndStructure() throws {
        let (store, _) = tempStore()
        var m = sample()
        m.elementChecklist = ["合同有效成立", "违约行为", "损害", "因果关系"]
        m.deadlines = [MatterDeadline(id: "d1", label: "举证期限", due: "2026-07-01[待核]")]
        m.pendingVerifications = ["《民法典》第577条[待核]"]
        try store.create(m)
        let loaded = try store.load("acme-2026")
        #expect(loaded == m)
    }

    @Test func close_archivesNotDeletes_andClearsActive() throws {
        let (store, root) = tempStore()
        try store.create(sample())
        try store.switchActive(to: "acme-2026")
        try store.close("acme-2026", at: "2026-09-01T00:00:00Z")
        #expect(store.activeMatter() == nil)                                  // active cleared
        #expect(store.list().isEmpty)                                         // not in active list
        #expect(store.list(includeArchived: true).map(\.slug) == ["acme-2026"]) // still readable
        #expect(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("_archived/acme-2026/matter.json").path))
        let reloaded = try store.load("acme-2026")
        #expect(reloaded.status == .archived)
    }

    @Test func duplicateSlug_throws() throws {
        let (store, _) = tempStore()
        try store.create(sample())
        #expect(throws: MatterStoreError.self) { try store.create(sample()) }
    }

    @Test func detach_keepsEnabledButNoActive() throws {
        let (store, _) = tempStore()
        try store.create(sample())
        try store.switchActive(to: "acme-2026")
        try store.detach()
        #expect(store.isEnabled == true)
        #expect(store.activeMatter() == nil)
    }

    @Test func invalidSlug_throws() {
        let (store, _) = tempStore()
        #expect(throws: MatterStoreError.self) {
            try store.create(Matter(slug: "../escape", title: "x", scene: .litigation, client: "y",
                                    createdAt: "t", updatedAt: "t"))
        }
    }
}
