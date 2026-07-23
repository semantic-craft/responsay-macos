import Foundation

/// The shared tail of the intent safety spine: a *verified* plan → source render → deterministic
/// correction → post-render guard → external outcome. Extracted so that both a fresh compile
/// (`IntentCompilationPipeline`) and a review-time candidate confirmation
/// (`IntentReviewResolver`) run the **identical** render+guard path — a confirmed candidate can
/// never take a weaker route to insertion than a first-pass result (#559 铁律: 候选确认必须重过
/// verifier + guard). The tail includes the preflight-cue veto (#561): callers pass the
/// deterministic scan of the SAME transcript the plan was verified against.
enum IntentPlanFinalizer {
    static func finalize(
        verified: IntentPlanVerifier.VerifiedPlan,
        cueHits: [IntentCuePreflight.Hit]
    ) -> IntentCompilationOutcome {
        if verified.plan.decision == .needsReview {
            return .needsReview(reason: .compilerRequested)
        }
        if let reason = IntentPlanCueCoverage.unexplainedReviewReason(hits: cueHits, verified: verified) {
            return .needsReview(reason: reason)
        }
        let draft = IntentSourceRenderer.render(verified)
        let finalText = TextCorrectionRules.apply(to: draft.text)
        guard IntentPostRenderGuard.accepts(draft: draft, finalText: finalText, verified: verified) else {
            return .safeUnavailable(reason: .postRenderGuardRejected)
        }
        let route: IntentInsertRoute = verified.plan.decision == .noIntentControl
            ? .ordinaryPolished
            : .intentPlan
        return .insertable(text: finalText, route: route)
    }
}
