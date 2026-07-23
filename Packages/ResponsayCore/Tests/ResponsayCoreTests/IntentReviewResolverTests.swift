import Foundation
import Testing
@testable import ResponsayCore

/// #559 — confirming a candidate or editing the draft must re-run the SAME verifier + guard, never
/// a bypass insert. The ambiguity fixture is "周三，不对，周四": one grounded reading is a change of
/// mind (keep only 周四), the other keeps both — each is a distinct verified plan.
struct IntentReviewResolverTests {
    private static let transcript = "周三，不对，周四"

    /// Build the two-candidate review proposal the way an injected result would.
    private static func ambiguityProposal() -> IntentReviewProposal {
        let units = IntentSourceSegmenter.segment(transcript)   // ["周三，","不对，","周四"]
        // Reading A — 改口：不对 supersedes 周三 → renders 周四 only.
        let correctionPlan = IntentPlan(
            version: 1,
            decision: .render,
            units: [
                .init(source: .init(units[0]), role: .content),
                .init(source: .init(units[1]), role: .correction),
                .init(source: .init(units[2]), role: .content)
            ],
            supersessions: [.init(winner: .init(units[2]), loser: .init(units[0]), cue: .init(units[1]))])
        // Reading B — 并列：keep everything as content (no correction) → renders the whole line.
        let keepBothPlan = IntentPlan(
            version: 1,
            decision: .render,
            units: units.map { .init(source: .init($0), role: .content) },
            supersessions: [])
        return IntentReviewProposal(
            transcript: transcript,
            sourceUnits: units,
            sanitizedDraft: "周四",
            candidates: [
                .init(id: "c-correction", value: "只保留「周四」", evidence: "改口", plan: correctionPlan),
                .init(id: "c-keepboth", value: "两者都写", evidence: "并列", plan: keepBothPlan)
            ],
            forbiddenFragments: ["不对", "周三"])
    }

    @Test func confirmingACandidateReVerifiesAndInsertsItsRenderedResult() {
        let proposal = Self.ambiguityProposal()

        // Confirming the 改口 reading runs verifier + render + guard → the superseded 周三 is gone.
        #expect(IntentReviewResolver.confirm(candidateID: "c-correction", in: proposal)
            == .insertable(text: "周四", route: .intentPlan))

        // Confirming the 并列 reading keeps the whole line — a genuinely different verified result,
        // proving the user's choice drives the outcome, not a fixed answer.
        #expect(IntentReviewResolver.confirm(candidateID: "c-keepboth", in: proposal)
            == .insertable(text: "周三，不对，周四", route: .intentPlan))
    }

    @Test func confirmingAnInvalidCandidatePlanIsSafeUnavailableNotBypassInsert() {
        let units = IntentSourceSegmenter.segment(Self.transcript)
        // A plan that fails coverage (only 1 of 3 units) must be REJECTED on confirm — the proof
        // that confirm re-verifies rather than trusting a candidate blindly.
        let brokenPlan = IntentPlan(
            version: 1, decision: .render,
            units: [.init(source: .init(units[0]), role: .content)],
            supersessions: [])
        let proposal = IntentReviewProposal(
            transcript: Self.transcript, sourceUnits: units,
            candidates: [.init(id: "c-broken", value: "坏", evidence: "x", plan: brokenPlan)])

        #expect(IntentReviewResolver.confirm(candidateID: "c-broken", in: proposal)
            == .safeUnavailable(reason: .invalidPlan))
    }

    @Test func confirmingAnUnofferedCandidateStaysInReview() {
        // Provenance: an id the compiler never offered cannot be conjured into an insert.
        #expect(IntentReviewResolver.confirm(candidateID: "ghost", in: Self.ambiguityProposal())
            == .needsReview(reason: .compilerRequested))
    }

    @Test func editingTheDraftReVerifiesBeforeInserting() {
        let proposal = Self.ambiguityProposal()

        // A clean edit inserts verbatim through the intent route.
        #expect(IntentReviewResolver.submit(editedDraft: "周四见", in: proposal)
            == .insertable(text: "周四见", route: .intentPlan))

        // Re-introducing a superseded / control fragment fails re-verification → stays in review,
        // never a silent unverified insert.
        #expect(IntentReviewResolver.submit(editedDraft: "周三见", in: proposal)
            == .needsReview(reason: .compilerRequested))
        #expect(IntentReviewResolver.submit(editedDraft: "不对，是周四", in: proposal)
            == .needsReview(reason: .compilerRequested))

        // An emptied draft is not insertable.
        #expect(IntentReviewResolver.submit(editedDraft: "   ", in: proposal)
            == .needsReview(reason: .compilerRequested))
    }

    @Test func genericProposalExposesNothingToConfirmOrEdit() {
        let proposal = IntentReviewProposal.generic(transcript: "随便说一句")
        #expect(proposal.content.sanitizedDraft == nil)
        #expect(proposal.content.candidates.isEmpty)
        #expect(proposal.content.isResolvable == false)
        // With no forbidden fragments a plain edit is still accepted (nothing to leak).
        #expect(IntentReviewResolver.submit(editedDraft: "随便说一句", in: proposal)
            == .insertable(text: "随便说一句", route: .intentPlan))
    }

    @Test func displayContentHidesThePlanAndSourceUnits() {
        // The projection the capsule sees carries only value + evidence — no plan, no units.
        let content = Self.ambiguityProposal().content
        #expect(content.candidates.map(\.value) == ["只保留「周四」", "两者都写"])
        #expect(content.candidates.map(\.evidence) == ["改口", "并列"])
        #expect(content.sanitizedDraft == "周四")
        #expect(content.isResolvable)
    }
}
