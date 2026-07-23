import Testing
import Foundation
@testable import ResponsayCore

/// 190 — MatterLinker: rules-first "是否已有案件?" — confirmable, never silent, off → nil.
struct MatterLinkerTests {
    private let linker = MatterLinker()

    private func entry(_ slug: String, title: String, client: String = "我方公司",
                       counterparties: [String] = [], lastActive: String) -> MatterLedgerEntry {
        MatterLedgerEntry(slug: slug, title: title, scene: .litigation, client: client,
                          counterparties: counterparties, status: .active, stage: .intake,
                          relatedMatters: [], openedAt: lastActive, lastActiveAt: lastActive)
    }

    @Test func off_returnsNil_neverSilent() {
        let ledger = [entry("acme", title: "Acme 买卖合同纠纷", counterparties: ["Acme 公司"], lastActive: "2026-06-01")]
        #expect(linker.suggest(selection: "Acme 公司 来函", ledger: ledger, enabled: false) == nil)
    }

    @Test func counterparty_match_isBest() throws {
        let ledger = [
            entry("acme", title: "Acme 买卖合同纠纷", counterparties: ["Acme 公司"], lastActive: "2026-06-01"),
            entry("zenith", title: "Zenith 劳动争议", counterparties: ["Zenith 公司"], lastActive: "2026-06-02"),
        ]
        let s = try #require(linker.suggest(selection: "今收到 Acme 公司 律师函，限7日履行", ledger: ledger, enabled: true))
        #expect(s.best?.slug == "acme")
        #expect(s.best?.reasons.contains { $0.contains("对方") } == true)
    }

    @Test func noMatch_emptyButNotNil() throws {
        let ledger = [entry("acme", title: "Acme 买卖合同纠纷", counterparties: ["Acme 公司"], lastActive: "2026-06-01")]
        let s = try #require(linker.suggest(selection: "一段无关的文本", ledger: ledger, enabled: true))
        #expect(s.candidates.isEmpty)
    }

    @Test func score_counterpartyBeatsKeywordOnly() throws {
        let ledger = [
            entry("a", title: "买卖合同纠纷", counterparties: ["甲公司"], lastActive: "2026-06-01"),
            entry("b", title: "买卖合同纠纷", counterparties: ["乙公司"], lastActive: "2026-06-01"),
        ]
        let s = try #require(linker.suggest(selection: "甲公司 的 买卖合同纠纷", ledger: ledger, enabled: true))
        #expect(s.best?.slug == "a")                 // cp(3)+kw(1)=4 beats kw-only(1)
        #expect(s.candidates.map(\.slug) == ["a", "b"])
    }

    @Test func recency_tiebreak() throws {
        let ledger = [
            entry("old", title: "买卖合同纠纷", lastActive: "2026-01-01"),
            entry("new", title: "买卖合同纠纷", lastActive: "2026-06-01"),
        ]
        let s = try #require(linker.suggest(selection: "买卖合同纠纷 的问题", ledger: ledger, enabled: true))
        #expect(s.candidates.map(\.slug) == ["new", "old"])   // equal score → newer first
    }

    @Test func neverAutoAssociates_storeActiveUnchanged() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("matters")
        let store = MatterStore(root: root)
        try store.create(Matter(slug: "acme", title: "Acme 买卖合同纠纷", scene: .litigation,
                                client: "我方公司", counterparties: ["Acme 公司"],
                                createdAt: "2026-06-01T00:00:00Z", updatedAt: "2026-06-01T00:00:00Z"))
        _ = linker.suggest(selection: "Acme 公司 来函", store: store)
        #expect(store.activeMatter() == nil)   // a suggestion never switches/associates
    }
}
