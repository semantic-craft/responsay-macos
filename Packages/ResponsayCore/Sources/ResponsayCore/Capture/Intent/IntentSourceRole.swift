import Foundation

public enum IntentSourceRole: String, Codable, Sendable {
    /// Renderable message content (unless superseded through an `IntentSupersession`).
    case content
    /// An explicit spoken correction cue (不对 / 我是说 / "scratch that"); must resolve into
    /// exactly one supersession, never rendered.
    case correction
    /// A spoken aside addressed to the app, not the recipient (#561): it may inform the plan
    /// (disambiguation, tone, "这句不用写"), but its source unit must never be rendered and may
    /// not participate in any supersession. Superseded *content* is not a role — it stays
    /// `content` and is excluded through the supersession's loser reference, so the
    /// relationship remains the single source of truth.
    case sideNote
    /// Spoken grounding evidence (#562): orthographic clues (如何的何) or descriptive hints that
    /// justify an entity candidate. Never rendered, never in a supersession; a render plan that
    /// marks grounding units must also resolve at least one entity (or abstain to needsReview),
    /// so a clue can never silently vanish while the misheard name stays.
    case grounding
}
