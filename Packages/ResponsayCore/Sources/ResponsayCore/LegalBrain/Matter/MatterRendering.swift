import Foundation

// MARK: - 188 Matter rendering (human-readable views; EMIT-ONLY)
//
// `matter.md` (generated from `matter.json`) + `_log.yaml` ledger are for humans / rollups.
// The source of truth is `matter.json`, so the YAML here is emit-only and never parsed back —
// arbitrary Chinese / colons / quotes in fields cannot corrupt loading.

extension Matter {
    /// A human-readable markdown rendering, regenerated on every write.
    public func markdownView() -> String {
        var s = "# Matter: \(title)\n\n"
        s += "- Slug: `\(slug)`\n"
        s += "- 场景: \(scene.rawValue)\n"
        s += "- 当事人: \(client)\n"
        s += "- 对方: \(counterparties.joined(separator: "、"))\n"
        s += "- 我方角色: \(role)\n"
        s += "- 阶段: \(stage.rawValue)\n"
        s += "- 保密: \(confidentiality.rawValue)\n"
        s += "- 状态: \(status.rawValue)\n"
        s += "- 开立: \(createdAt) · 更新: \(updatedAt)\n"
        if !relatedMatters.isEmpty { s += "- 关联案: \(relatedMatters.joined(separator: ", "))\n" }
        s += "\n## 关键事实\n\n\(keyFacts.isEmpty ? "（待补）" : keyFacts)\n"
        s += listSection("要件表", elementChecklist)
        s += listSection("证据清单", evidenceList)
        if !deadlines.isEmpty {
            s += "\n## 时间线·期限\n\n"
            for d in deadlines { s += "- \(d.label): \(d.due)\(d.note.map { "（\($0)）" } ?? "")\n" }
        }
        s += listSection("待核清单", pendingVerifications)
        s += listSection("草稿历史", draftHistory)
        s += listSection("本案覆盖项", overrides)
        return s
    }

    private func listSection(_ title: String, _ items: [String]) -> String {
        guard !items.isEmpty else { return "" }
        return "\n## \(title)\n\n" + items.map { "- \($0)" }.joined(separator: "\n") + "\n"
    }
}

enum MatterLedgerYAML {
    /// Emit a human-readable YAML rollup. Strings are double-quoted + escaped so the file is
    /// always valid YAML even with Chinese / colons / quotes. EMIT-ONLY (never parsed back).
    static func render(enabled: Bool, active: String?, entries: [MatterLedgerEntry]) -> String {
        var s = "# Matter ledger — generated; source of truth is each matters/<slug>/matter.json\n"
        s += "enabled: \(enabled)\n"
        s += "active: \(active.map(quote) ?? "null")\n"
        s += "matters:\n"
        if entries.isEmpty { return s + "  []\n" }
        for e in entries {
            s += "  - slug: \(quote(e.slug))\n"
            s += "    title: \(quote(e.title))\n"
            s += "    scene: \(quote(e.scene.rawValue))\n"
            s += "    client: \(quote(e.client))\n"
            s += "    counterparties: [\(e.counterparties.map(quote).joined(separator: ", "))]\n"
            s += "    status: \(quote(e.status.rawValue))\n"
            s += "    stage: \(quote(e.stage.rawValue))\n"
            s += "    relatedMatters: [\(e.relatedMatters.map(quote).joined(separator: ", "))]\n"
            s += "    openedAt: \(quote(e.openedAt))\n"
            s += "    lastActiveAt: \(quote(e.lastActiveAt))\n"
        }
        return s
    }

    private static func quote(_ raw: String) -> String {
        let escaped = raw
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }
}
