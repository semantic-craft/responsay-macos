import Foundation

public enum HotwordLearningDecision: Sendable, Equatable {
    /// Add to the auto dictionary. `notify` = surface the undo toast — true only for specialized
    /// terms (法律专名/专业术语/案号); ordinary terms are added silently (PRD 2026-06-19 §3,
    /// Tier 1 vs Tier 2). Either way the add is recorded and undoable in the audit panel.
    case add(HotwordCandidateProposal, notify: Bool)
    /// Hold for the user to confirm later (pending) — a specialized term below the high-confidence
    /// bar, which we never auto-apply (Tier 4).
    case confirm(HotwordCandidateProposal)
    case ignore(HotwordCandidateProposal, reason: String)
}
