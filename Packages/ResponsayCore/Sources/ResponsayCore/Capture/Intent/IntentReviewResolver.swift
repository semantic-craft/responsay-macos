import Foundation

/// Turns a user decision inside the review capsule back into a fresh `IntentCompilationOutcome`,
/// always through the same safety spine (#559 铁律: 候选确认、草稿编辑后必须重新过 verifier + guard,
/// 不得绕过校验插入).
///
/// - `confirm` re-runs the plan verifier + render + post-render guard on the chosen candidate's
///   plan — a confirmed grounded name has no cheaper path to insertion than a first-pass result.
/// - `submit` runs the edited-draft guard on freely-edited text; failure stays in review.
enum IntentReviewResolver {
    static func confirm(candidateID: String, in proposal: IntentReviewProposal) -> IntentCompilationOutcome {
        // Provenance: only a candidate the compiler actually offered may be confirmed — an
        // arbitrary value can never be conjured into an insert. Unknown id → stay in review.
        guard let candidate = proposal.candidates.first(where: { $0.id == candidateID }) else {
            return .needsReview(reason: .compilerRequested)
        }
        let verified: IntentPlanVerifier.VerifiedPlan
        do {
            verified = try IntentPlanVerifier.verify(
                candidate.plan, sourceUnits: proposal.sourceUnits, transcript: proposal.transcript,
                entityCandidates: proposal.entityCandidates)
        } catch {
            return .safeUnavailable(reason: .invalidPlan)
        }
        // cueHits deliberately empty, and no conflict arbiter here (#561/#562): those vetoes
        // exist to route doubt INTO review. The human just resolved it by confirming this
        // candidate — re-vetoing would livelock the capsule (confirm → review → confirm) and
        // overrule the user. Structural safety still holds: the plan re-ran the verifier above
        // (including the entity whitelist) and the render still passes the post-render guard.
        return IntentPlanFinalizer.finalize(verified: verified, cueHits: [])
    }

    static func submit(editedDraft: String, in proposal: IntentReviewProposal) -> IntentCompilationOutcome {
        guard IntentEditedDraftGuard.accepts(
            editedDraft: editedDraft, forbiddenFragments: proposal.forbiddenFragments) else {
            // Re-verification failed → no unverified insert; the capture stays in review.
            return .needsReview(reason: .compilerRequested)
        }
        return .insertable(text: editedDraft, route: .intentPlan)
    }
}
