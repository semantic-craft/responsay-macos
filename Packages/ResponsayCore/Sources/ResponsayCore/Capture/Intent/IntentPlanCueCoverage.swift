import Foundation

/// The preflight-consistency half of the veto (#561/#562, spec decision 20/22): every source
/// unit the deterministic `IntentCuePreflight` flagged must be *explained* by the verified plan
/// — classified as `correction`, `sideNote` or `grounding`, i.e. acknowledged control speech
/// that can never render. A flagged unit left as plain `content` (even a supersession loser)
/// means the plan and the local scanner disagree about what is control speech, so the capture
/// stops in review instead of trusting either side. A miss (no hits) returns nil and
/// authorizes nothing.
enum IntentPlanCueCoverage {
    static func unexplainedReviewReason(
        hits: [IntentCuePreflight.Hit],
        verified: IntentPlanVerifier.VerifiedPlan
    ) -> IntentReviewReason? {
        guard !hits.isEmpty else { return nil }
        let roleByID = Dictionary(
            uniqueKeysWithValues: verified.plan.units.map { ($0.source.sourceID, $0.role) })
        let unexplained = hits.filter { roleByID[$0.sourceID] == .content || roleByID[$0.sourceID] == nil }
        guard !unexplained.isEmpty else { return nil }
        if unexplained.contains(where: { $0.kind == .correction }) { return .unexplainedCorrectionCue }
        if unexplained.contains(where: { $0.kind == .grounding }) { return .unexplainedGroundingCue }
        return .unexplainedSideNoteCue
    }
}
