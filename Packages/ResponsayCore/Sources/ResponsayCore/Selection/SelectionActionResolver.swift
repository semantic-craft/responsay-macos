import Foundation

/// Decides the **gated action set** for a text selection (issue 127 / ADR-0022).
/// Redesigned 划词菜单: the menu is fixed-structure now. Instant tools (翻译 / 朗读)
/// + the legal-research smart row (来源核验 / 来源辅助检索 / 任意提问) are always offered;
/// a term-shaped fragment additionally gets 加入词典. 实务辅助 (the practice-skill
/// dropdown) is not a `SelectionAction` — the menu builds it from enabled skills.
/// Empty selection → nothing (downgrade, ADR-0008).
public struct SelectionActionResolver: Sendable {
    public init() {}

    /// `scene` is accepted for call-site compatibility but no longer gates the set:
    /// the smart row is fixed regardless of scene (the explicit 来源核验 / 来源辅助检索 /
    /// 实务辅助 entries replaced the opaque auto-routed 法律技能 palette).
    public func actions(
        classification: SelectionClassification,
        scene: SceneStageClassification? = nil,
        hasSelection: Bool = true
    ) -> [SelectionAction] {
        guard hasSelection else { return [] }

        // Instant tools (icon row) + the fixed legal-research smart row. Order here is
        // the canonical order; the menu view places each into its row by identity.
        var actions: [SelectionAction] = [.translate, .readAloud, .verify, .assistedSearch, .normalizeTypography, .ask]

        // Term-shaped fragment (1–2 words / 短专名, not a clause, carries letters) →
        // offer the recognition dictionary (300). Sentences bias prose, not hotwords.
        if !classification.isSentenceShaped, classification.script != .other {
            actions.append(.addToDictionary)
        }
        return actions
    }
}
