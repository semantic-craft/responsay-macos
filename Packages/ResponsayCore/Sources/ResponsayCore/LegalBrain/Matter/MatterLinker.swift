import Foundation

// MARK: - 190 MatterLinker — rules-first "是否已有案件?"
//
// Given the selected text, deterministically (no model) rank which EXISTING matter it most
// likely belongs to, by matching the portfolio ledger (188) on 对方名 / 当事人 / 案由关键词,
// with recency as a tiebreak. The result is a *confirmable suggestion* — the linker never
// auto-associates and never runs when the workspace is OFF (default). Mirrors the router's
// "rules before model" stance. Foundation-only.

public struct MatterMatchCandidate: Codable, Sendable, Equatable {
    public let slug: String
    public let score: Double
    public let reasons: [String]   // 如 "命中对方「Acme 公司」" / "命中关键词「买卖合同」"

    public init(slug: String, score: Double, reasons: [String]) {
        self.slug = slug
        self.score = score
        self.reasons = reasons
    }
}

/// A confirmable suggestion. The capsule renders it as `属于〔best.slug〕? 是 / 新建 / 不关联`.
/// Empty `candidates` → offer 新建 / 不关联 only. `nil` (workspace off) → no chip at all.
public struct MatterLinkSuggestion: Codable, Sendable, Equatable {
    public let candidates: [MatterMatchCandidate]   // ranked, best first
    public var best: MatterMatchCandidate? { candidates.first }
    public init(candidates: [MatterMatchCandidate]) { self.candidates = candidates }
}

public struct MatterLinker: Sendable {
    public init() {}

    // Scoring weights — names are distinctive (strong), 案由关键词 weaker.
    private static let counterpartyWeight = 3.0
    private static let clientWeight = 2.0
    private static let keywordWeight = 1.0

    /// Rules-first ranking. Returns nil when the workspace is OFF — never a silent
    /// auto-association; the caller shows a confirmable chip from the suggestion.
    public func suggest(
        selection: String,
        ledger: [MatterLedgerEntry],
        enabled: Bool,
        topK: Int = 3
    ) -> MatterLinkSuggestion? {
        guard enabled else { return nil }
        guard !selection.isEmpty else { return MatterLinkSuggestion(candidates: []) }

        var scored: [MatterMatchCandidate] = []
        for e in ledger where e.status == .active {
            var score = 0.0
            var reasons: [String] = []
            for cp in e.counterparties where !cp.isEmpty && selection.contains(cp) {
                score += Self.counterpartyWeight
                reasons.append("命中对方「\(cp)」")
            }
            if !e.client.isEmpty, selection.contains(e.client) {
                score += Self.clientWeight
                reasons.append("命中当事人「\(e.client)」")
            }
            for token in Self.keywords(e.title) where selection.contains(token) {
                score += Self.keywordWeight
                reasons.append("命中关键词「\(token)」")
            }
            if score > 0 { scored.append(MatterMatchCandidate(slug: e.slug, score: score, reasons: reasons)) }
        }

        // score desc, then most-recently-active first (deterministic tiebreak).
        let recency = Dictionary(ledger.map { ($0.slug, $0.lastActiveAt) }, uniquingKeysWith: { a, _ in a })
        scored.sort { a, b in
            a.score != b.score ? a.score > b.score : (recency[a.slug] ?? "") > (recency[b.slug] ?? "")
        }
        return MatterLinkSuggestion(candidates: Array(scored.prefix(topK)))
    }

    /// Convenience over a store (reads its ledger + enabled flag).
    public func suggest(selection: String, store: MatterStore, topK: Int = 3) -> MatterLinkSuggestion? {
        suggest(selection: selection, ledger: store.list(), enabled: store.isEnabled, topK: topK)
    }

    /// 案由 keywords: separator-split chunks of length ≥ 2, de-duplicated.
    static func keywords(_ title: String) -> [String] {
        let seps = CharacterSet(charactersIn: " 　,，。、·.-—/／()（）：:；;")
        return Array(Set(title.components(separatedBy: seps).filter { $0.count >= 2 }))
    }
}
