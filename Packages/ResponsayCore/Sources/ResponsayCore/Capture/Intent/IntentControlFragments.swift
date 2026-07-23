import Foundation

/// Control/abandoned spans of a verified plan that must never (re)appear in any output text:
/// non-content units (correction cues, side notes, grounding clues) and superseded losers.
/// Shared by the review proposal's edited-draft guard (#559/#562) and the post-polish guard
/// (#564), so every re-entry door applies the identical fragment set.
enum IntentControlFragments {
    static func fragments(in verified: IntentPlanVerifier.VerifiedPlan) -> [String] {
        let loserIDs = Set(verified.plan.supersessions.map(\.loser.sourceID))
        return verified.plan.units.compactMap { unit in
            guard unit.role != .content || loserIDs.contains(unit.source.sourceID) else { return nil }
            let fragment = unit.source.exactQuote.trimmingCharacters(
                in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            return fragment.isEmpty ? nil : fragment
        }
    }
}
