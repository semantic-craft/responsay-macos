import Foundation

// 559 — the Intent-aware review capsule's actions. Every path that could reach the target field
// (confirm a candidate, submit an edited draft) re-runs the verifier + guard through
// `IntentReviewResolver`; the two escape hatches (retry, explicit convert-to-ordinary-Dictate)
// are independent user decisions, never automatic collapses of a needs-review. Copying the safe
// draft and cancelling stay side-effect-free (no History / learning — that is #565).
extension QuickCaptureViewModel {
    /// The display-only projection the capsule renders for a needs-review (sanitized draft +
    /// candidate value/evidence labels). Strips the plan and source units by construction.
    public var intentReviewContent: IntentReviewContent? { intentReviewProposal?.content }
    /// The "current safe draft" copy target (#559 acceptance): the sanitized draft when one exists,
    /// otherwise the user's own words. Never the provider response or a superseded/side-note span.
    public var intentSafeCopyText: String { intentReviewContent?.sanitizedDraft ?? transcript }

    /// Enter the review capsule with a resolvable proposal. The live compiler passes a `.generic`
    /// proposal; an injected result (tests / DEBUG fixture / future grounding) passes candidates +
    /// a sanitized draft. Only ever holds the raw transcript, plan, and candidates in memory.
    func presentIntentReview(_ proposal: IntentReviewProposal, reason: IntentReviewReason = .compilerRequested) {
        intentReviewProposal = proposal
        intentReviewReverifyRejected = false
        intentCaptureState = .needsReview(reason)
        phase = .review
    }

    /// Confirm a grounded candidate → re-run verifier + guard on its plan. A valid result inserts
    /// through the intent path; anything else stays in review (never a bypass). A confirmation that
    /// produces an insertable result is the ONE user signal that may learn the grounded entity's
    /// `surface → canonical` alias (#565) — emitted here (gated + persisted by the macOS sink),
    /// computed from the local proposal BEFORE `applyIntentReviewOutcome` clears it.
    public func confirmIntentCandidate(id: String) async {
        guard phase == .review, let proposal = intentReviewProposal else { return }
        intentReviewReverifyRejected = false
        let outcome = IntentReviewResolver.confirm(candidateID: id, in: proposal)
        if let alias = IntentConfirmedAliasLearning.learnable(
            confirmedCandidateID: id, in: proposal, outcome: outcome) {
            intentConfirmedAliasSink?(alias)
        }
        await applyIntentReviewOutcome(outcome)
    }

    /// Submit a user-edited sanitized draft → re-verify (non-empty, no forbidden span). Pass fails
    /// → insert; fail → stay in review with the proposal intact so the user can edit again.
    public func submitIntentEditedDraft(_ text: String) async {
        guard phase == .review, let proposal = intentReviewProposal else { return }
        intentReviewReverifyRejected = false
        await applyIntentReviewOutcome(IntentReviewResolver.submit(editedDraft: text, in: proposal))
    }

    /// Re-run intent compilation on the same final transcript (a fresh attempt, e.g. after a
    /// transient provider failure). Re-enters the compiling state; late results from the previous
    /// attempt are already dropped by the generation guard.
    public func retryIntentCompilation() async {
        guard phase == .review else { return }
        let text = transcript
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { discard(); return }
        clearIntentReviewState()
        result = nil
        activeOutputMode = .intentAwareDictation
        phase = .thinking
        await insertIntentAwareTranscript(text)
    }

    /// The explicit, independent "转普通 Dictate" — NOT an automatic fallback (#559 铁律). Runs the
    /// ordinary Polished Dictate path on the same transcript; its visible route (普通整理, with its
    /// own insert + History) tells the user semantic organization was NOT applied.
    public func convertIntentToOrdinaryDictate() async {
        guard phase == .review else { return }
        let text = transcript
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { discard(); return }
        clearIntentReviewState()
        result = nil
        activeOutputMode = .polishedTranscript
        phase = .thinking
        await insertPolishedTranscript(text)
    }

    private func clearIntentReviewState() {
        intentReviewProposal = nil
        intentReviewReverifyRejected = false
        intentCaptureState = nil
    }

    private func applyIntentReviewOutcome(_ outcome: IntentCompilationOutcome) async {
        switch outcome {
        case let .insertable(text, route):
            clearIntentReviewState()
            // The single intent insert path (no History / correction offer), bound to the original
            // target with a safe-undo transaction (#560).
            await commitIntentInsert(
                CaptureResultFactory.intentAware(source: transcript, output: text, route: route))
        case .needsReview:
            // Re-verification did not pass → stay put with the proposal intact. The user can pick
            // another candidate or edit again; nothing unverified reaches the field.
            intentReviewReverifyRejected = true
        case let .safeUnavailable(reason):
            intentReviewProposal = nil
            intentCaptureState = .safeUnavailable(reason)
        }
    }
}
