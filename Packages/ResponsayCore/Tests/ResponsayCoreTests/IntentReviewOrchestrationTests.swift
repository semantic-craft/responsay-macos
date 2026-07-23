import Foundation
import Testing
@testable import ResponsayCore

/// #559 — the four terminal states and the review-capsule actions, driven through the VM with
/// injected results (no real provider). Confirm / edit re-verify; retry re-compiles; convert is an
/// explicit ordinary-Dictate route; none of the non-insert states leak into History or learning.
@MainActor
struct IntentReviewOrchestrationTests {
    private static let transcript = "周三，不对，周四"

    private static func ambiguityProposal() -> IntentReviewProposal {
        let units = IntentSourceSegmenter.segment(transcript)
        let correctionPlan = IntentPlan(
            version: 1, decision: .render,
            units: [
                .init(source: .init(units[0]), role: .content),
                .init(source: .init(units[1]), role: .correction),
                .init(source: .init(units[2]), role: .content)
            ],
            supersessions: [.init(winner: .init(units[2]), loser: .init(units[0]), cue: .init(units[1]))])
        let keepBothPlan = IntentPlan(
            version: 1, decision: .render,
            units: units.map { .init(source: .init($0), role: .content) }, supersessions: [])
        return IntentReviewProposal(
            transcript: transcript, sourceUnits: units, sanitizedDraft: "周四",
            candidates: [
                .init(id: "c-correction", value: "只保留「周四」", evidence: "改口", plan: correctionPlan),
                .init(id: "c-keepboth", value: "两者都写", evidence: "并列", plan: keepBothPlan)
            ],
            forbiddenFragments: ["不对", "周三"])
    }

    private static func makeVM(
        inserter: MockTextInserter = MockTextInserter(),
        compiler: (any IntentPlanCompiler)? = nil
    ) -> (QuickCaptureViewModel, MockTextInserter, FileCaptureStore) {
        let store = FileCaptureStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("json"))
        let routeProvider: (@MainActor () -> IntentRoutePolicy)?
        if compiler == nil { routeProvider = nil } else { routeProvider = { .injectedCompiler } }
        let vm = QuickCaptureViewModel(
            speech: MockSpeechCaptureService(), coach: MockCoachAPI(), store: store,
            inserter: inserter, polisher: nil,
            intentCompiler: compiler,
            intentRoutePolicyProvider: routeProvider)
        return (vm, inserter, store)
    }

    @Test func confirmingCandidateReVerifiesThenInsertsThroughIntentPathNoHistory() async throws {
        let (vm, inserter, store) = Self.makeVM()
        vm.transcript = Self.transcript
        vm.presentIntentReview(Self.ambiguityProposal())
        #expect(vm.phase == .review)
        #expect(vm.intentReviewContent?.candidates.count == 2)

        await vm.confirmIntentCandidate(id: "c-correction")

        #expect(vm.phase == .idle)
        #expect(inserter.inserted == ["周四"])            // superseded 周三 gone
        // #565: the confirmed final persists (route + outcome, raw not retained); session cleared.
        let saved = try #require(try store.recent(10).first)
        #expect(saved.sourceText == nil)
        #expect(saved.idiomatic == "周四")
        #expect(saved.intentRoute == .intentPlan)
        #expect(saved.intentOutcome == .inserted)
        #expect(try store.recent(10).count == 1)
        #expect(vm.captureResult == nil)
        #expect(vm.transcript.isEmpty)
        #expect(vm.intentReviewProposal == nil)
        #expect(vm.intentCaptureState == nil)
        #expect(vm.revertableInsertion == nil)            // never the ↩原文 semantics
        #expect(vm.correctionOffer == nil)
    }

    @Test func rejectedEditStaysInReviewWithProposalIntactAndNoInsert() async throws {
        let (vm, inserter, _) = Self.makeVM()
        vm.transcript = Self.transcript
        vm.presentIntentReview(Self.ambiguityProposal())

        await vm.submitIntentEditedDraft("周三见")   // reintroduces the superseded 周三

        #expect(vm.phase == .review)
        #expect(vm.intentReviewReverifyRejected)
        #expect(vm.intentReviewProposal != nil)          // can try again
        #expect(vm.intentCaptureState == .needsReview(.compilerRequested))
        #expect(inserter.inserted.isEmpty)               // no unverified insert
    }

    @Test func cleanEditReVerifiesAndInsertsExactly() async throws {
        let (vm, inserter, store) = Self.makeVM()
        vm.transcript = Self.transcript
        vm.presentIntentReview(Self.ambiguityProposal())

        await vm.submitIntentEditedDraft("周四下午见")

        #expect(vm.phase == .idle)
        #expect(inserter.inserted == ["周四下午见"])
        let saved = try #require(try store.recent(10).first)   // #565: edited final persists
        #expect(saved.sourceText == nil)
        #expect(saved.idiomatic == "周四下午见")
        #expect(saved.intentRoute == .intentPlan)
        #expect(saved.intentOutcome == .inserted)
        #expect(vm.intentReviewReverifyRejected == false)
    }

    @Test func convertToOrdinaryDictateIsAnExplicitVisibleRouteNotACollapse() async throws {
        // No polisher → ordinary Polished degrades to the verbatim transcript, but the point is the
        // ROUTE: it lands as .polishSameLanguage (ordinary Dictate), not an intent result, and the
        // active mode flips so the capsule badge stops saying 校验成稿.
        let (vm, inserter, store) = Self.makeVM()
        vm.transcript = Self.transcript
        vm.presentIntentReview(Self.ambiguityProposal())

        await vm.convertIntentToOrdinaryDictate()

        #expect(vm.phase == .idle)
        #expect(inserter.inserted == [Self.transcript])
        #expect(vm.captureResult?.mode == .polishSameLanguage)
        #expect(vm.captureResult?.intentInsertRoute == nil)
        #expect(vm.activeOutputMode == .polishedTranscript)
        #expect(vm.intentReviewProposal == nil)
        #expect(vm.intentCaptureState == nil)
        #expect(try !store.recent(10).isEmpty)           // ordinary Dictate keeps its own History
    }

    @Test func retryRecompilesTheSameFinalTranscript() async throws {
        let compiler = FixtureIntentCompiler { input in
            try JSONEncoder().encode(IntentPlan(
                version: 1, decision: .noIntentControl,
                units: input.sourceUnits.map { .init(source: .init($0), role: .content) },
                supersessions: []))
        }
        let (vm, inserter, store) = Self.makeVM(compiler: compiler)
        vm.transcript = "A"
        vm.presentIntentReview(.generic(transcript: "A"))

        await vm.retryIntentCompilation()

        #expect(vm.phase == .idle)
        #expect(inserter.inserted == ["A"])
        #expect(try store.recent(10).first?.intentRoute == .ordinaryPolished)   // #565: persisted route
        #expect(vm.captureResult == nil)
        #expect(vm.intentReviewProposal == nil)
    }

    @Test func safeCopyTextPrefersSanitizedDraftElseUsersOwnWords() {
        let (vm, _, _) = Self.makeVM()
        vm.transcript = Self.transcript
        vm.presentIntentReview(Self.ambiguityProposal())
        #expect(vm.intentSafeCopyText == "周四")           // the sanitized draft

        // A generic review with no draft copies the user's own words, never a provider payload.
        vm.presentIntentReview(.generic(transcript: Self.transcript))
        #expect(vm.intentSafeCopyText == Self.transcript)
    }

    @Test func reviewActionsAreNoOpsOutsideReview() async {
        let (vm, inserter, _) = Self.makeVM()
        vm.transcript = "A"                                // phase == .idle, no proposal
        await vm.confirmIntentCandidate(id: "x")
        await vm.submitIntentEditedDraft("anything")
        #expect(vm.phase == .idle)
        #expect(inserter.inserted.isEmpty)
    }
}
