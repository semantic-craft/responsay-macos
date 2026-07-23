import Foundation

/// The off-screen re-verification context for a needs-review capture. It holds everything needed
/// to re-run the safety spine when the user confirms a candidate or edits the draft — the source
/// units, the transcript, each candidate's resolving `IntentPlan`, and the entity candidate
/// table — none of which may ever reach the capsule. The type is `public` only so a
/// needs-review outcome can carry it through the (public) transform seams; every member stays
/// `internal`, so the macOS view can only ever see `content` (an `IntentReviewContent`) via the
/// view model — the plan and raw spans remain *structurally* un-renderable, not merely by
/// convention (#559: 绝不显示内部 plan / raw 旁注).
public struct IntentReviewProposal: Sendable, Equatable {
    let transcript: String
    let sourceUnits: [IntentSourceUnit]
    let sanitizedDraft: String?
    let candidates: [Candidate]
    /// Trimmed original text of the source units that must NOT appear in any confirmed or edited
    /// output — correction cues, superseded losers, side notes and grounding clues. The
    /// edited-draft guard rejects an edit that reintroduces one, so control/abandoned speech
    /// can't leak back in through the editor.
    let forbiddenFragments: [String]
    /// The app-built whitelist table (#562) — confirm re-runs the verifier against it.
    let entityCandidates: [IntentEntityCandidate]

    struct Candidate: Sendable, Equatable, Identifiable {
        let id: String
        let value: String
        let evidence: String
        /// The plan re-run through `IntentPlanVerifier` on confirm; never rendered.
        let plan: IntentPlan
    }

    init(
        transcript: String,
        sourceUnits: [IntentSourceUnit],
        sanitizedDraft: String? = nil,
        candidates: [Candidate] = [],
        forbiddenFragments: [String] = [],
        entityCandidates: [IntentEntityCandidate] = []
    ) {
        self.transcript = transcript
        self.sourceUnits = sourceUnits
        self.sanitizedDraft = sanitizedDraft
        self.candidates = candidates
        self.forbiddenFragments = forbiddenFragments
        self.entityCandidates = entityCandidates
    }

    /// The generic "please confirm" review the live compiler asks for: no draft, no candidates,
    /// nothing to leak. The user can still copy their own words, retry, convert, or cancel.
    static func generic(transcript: String) -> IntentReviewProposal {
        IntentReviewProposal(transcript: transcript, sourceUnits: IntentSourceSegmenter.segment(transcript))
    }

    /// The display projection — the only thing the capsule sees.
    var content: IntentReviewContent {
        IntentReviewContent(
            sanitizedDraft: sanitizedDraft,
            candidates: candidates.map {
                IntentReviewContent.Candidate(id: $0.id, value: $0.value, evidence: $0.evidence)
            })
    }
}
