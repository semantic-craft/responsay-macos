import Foundation

/// Decision 16's "唯一或弃权" arbiter (#562): when a verified plan selects a candidate whose slot
/// is contested (another whitelisted candidate proves a DIFFERENT spelling for an overlapping
/// span), auto-normalization is off the table — the capture stops in review with the whole
/// contested group as confirmable candidates. Runs on the first-pass pipeline only: confirming
/// a candidate in the capsule IS the resolution (same no-livelock boundary as the #561 cue
/// veto), and that confirm still re-runs verifier + render + guard through the resolver.
enum IntentEntityConflictArbiter {
    static func review(
        verified: IntentPlanVerifier.VerifiedPlan,
        transcript: String
    ) -> IntentCompilationOutcome? {
        guard let contested = verified.selectedCandidates.first(where: { candidate in
            !IntentEntityCandidateTable.conflicts(with: candidate, in: verified.entityCandidates).isEmpty
        }) else { return nil }

        let alternatives = IntentEntityCandidateTable.conflicts(
            with: contested, in: verified.entityCandidates)
        let group = [contested] + alternatives
        let candidates = group.map { candidate in
            IntentReviewProposal.Candidate(
                id: candidate.id,
                value: candidate.value,
                evidence: candidate.provenance.evidenceLabel,
                plan: plan(selecting: candidate, insteadOf: contested, in: verified.plan))
        }

        // Draft preview with the contested slot left exactly as spoken — no side takes effect
        // until the user picks one.
        let neutral = IntentPlanVerifier.VerifiedPlan(
            plan: verified.plan,
            sourceUnits: verified.sourceUnits,
            renderedSourceIDs: verified.renderedSourceIDs,
            entityCandidates: verified.entityCandidates,
            selectedCandidates: verified.selectedCandidates.filter { $0.id != contested.id })
        let sanitizedDraft = TextCorrectionRules.apply(to: IntentSourceRenderer.draftText(for: neutral))

        return .needsReview(
            reason: .ambiguousEntityCandidates,
            proposal: IntentReviewProposal(
                transcript: transcript,
                sourceUnits: verified.sourceUnits,
                sanitizedDraft: sanitizedDraft,
                candidates: candidates,
                forbiddenFragments: IntentControlFragments.fragments(in: verified),
                entityCandidates: verified.entityCandidates))
    }

    /// #575 — the lazy-selection degradation: a verified render plan that marks grounding
    /// units but selects NO candidate used to be discarded (blocked card, dead end). Weak
    /// models make that slip stochastically even when the plan is otherwise byte-perfect
    /// (live eval 2026-07-13), so with a non-empty table the capture now stops in a
    /// candidate-confirm review: the clue-proved candidates are offered, one tap resolves,
    /// and the confirm re-runs verifier + render + guard. Never silent — the alternative
    /// (auto-inserting with the clues dropped and the name uncorrected) is exactly what the
    /// old verifier rule existed to prevent.
    static func unresolvedGroundingReview(
        verified: IntentPlanVerifier.VerifiedPlan,
        transcript: String
    ) -> IntentCompilationOutcome? {
        guard verified.plan.decision == .render,
              verified.plan.units.contains(where: { $0.role == .grounding }),
              verified.selectedCandidates.isEmpty,
              !verified.entityCandidates.isEmpty
        else { return nil }

        let proven = verified.entityCandidates.filter { $0.provenance == .spokenClue }
        let candidates = proven.map { candidate in
            IntentReviewProposal.Candidate(
                id: candidate.id,
                value: candidate.value,
                evidence: candidate.provenance.evidenceLabel,
                plan: IntentPlan(
                    version: verified.plan.version,
                    decision: verified.plan.decision,
                    units: verified.plan.units,
                    supersessions: verified.plan.supersessions,
                    entities: verified.plan.entities + [candidate.id]))
        }
        let sanitizedDraft = TextCorrectionRules.apply(to: IntentSourceRenderer.draftText(for: verified))

        return .needsReview(
            reason: .unexplainedGroundingCue,
            proposal: IntentReviewProposal(
                transcript: transcript,
                sourceUnits: verified.sourceUnits,
                sanitizedDraft: sanitizedDraft,
                candidates: candidates,
                forbiddenFragments: IntentControlFragments.fragments(in: verified),
                entityCandidates: verified.entityCandidates))
    }

    private static func plan(
        selecting candidate: IntentEntityCandidate,
        insteadOf contested: IntentEntityCandidate,
        in plan: IntentPlan
    ) -> IntentPlan {
        IntentPlan(
            version: plan.version,
            decision: plan.decision,
            units: plan.units,
            supersessions: plan.supersessions,
            entities: plan.entities.map { $0 == contested.id ? candidate.id : $0 })
    }

}
