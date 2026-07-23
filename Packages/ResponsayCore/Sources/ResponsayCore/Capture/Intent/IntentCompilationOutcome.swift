import Foundation

public enum IntentCompilationOutcome: Sendable, Equatable {
    case insertable(text: String, route: IntentInsertRoute)
    /// `proposal` carries the off-screen review context (#562: contested entity candidates the
    /// user picks from). nil ⇒ the generic confirm review. The capsule still only ever sees the
    /// proposal's `content` projection.
    case needsReview(reason: IntentReviewReason, proposal: IntentReviewProposal?)
    case safeUnavailable(reason: IntentUnavailableReason)

    /// Proposal-less convenience so existing call sites and assertions keep reading naturally.
    static func needsReview(reason: IntentReviewReason) -> IntentCompilationOutcome {
        .needsReview(reason: reason, proposal: nil)
    }
}
