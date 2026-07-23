import Foundation
import Testing
@testable import ResponsayCore

/// The canonical 释字 shape (from the #562 flow): misheard name + clue clause + trailing content.
private let clueTranscript = "贺正杰，如何的何、纯正的正、杰出的杰，请转告他"

private func cluePlan(_ input: IntentCompilerInput, entities: [String]) -> IntentPlan {
    IntentPlan(
        version: 1, decision: .render,
        units: [
            .init(source: .init(input.sourceUnits[0]), role: .content),
            .init(source: .init(input.sourceUnits[1]), role: .grounding),
            .init(source: .init(input.sourceUnits[2]), role: .content)
        ],
        supersessions: [], entities: entities)
}

private func contestedCompiler() -> FixtureIntentCompiler {
    FixtureIntentCompiler { input in
        try JSONEncoder().encode(cluePlan(input, entities: [input.entityCandidates[0].id]))
    }
}

/// A contested-entity review: the spoken clue proves "何正杰", a confirmed alias proves "何政杰"
/// for the SAME misheard span "贺正杰" → 唯一或弃权 stops in review with both candidates.
private func contestedProposal() async -> IntentReviewProposal {
    let outcome = await IntentCompilationPipeline(compiler: contestedCompiler()).compile(
        finalTranscript: clueTranscript, locale: .chinese, allowedContext: nil,
        routePolicy: .injectedCompiler,
        grounding: IntentGroundingSources(aliases: [.init(surface: "贺正杰", canonical: "何政杰")]))
    guard case let .needsReview(_, proposal?) = outcome else {
        fatalError("expected contested-entity review, got \(outcome)")
    }
    return proposal
}

/// #565 — confirmed-candidate learning. `IntentConfirmedAliasLearning` decides what a review
/// confirmation authorizes learning, and the VM emits exactly that (and only that) to the injected
/// sink: a grounded-entity confirmation that inserted, never an auto-adopted unique candidate, a
/// correction-chain choice, a rejected re-verification, or a cancel.
@MainActor
struct IntentConfirmedLearningTests {
    private func makeVM(
        compiler: (any IntentPlanCompiler)?,
        grounding: IntentGroundingSources = .empty,
        transcript: String = clueTranscript,
        sink: @escaping @MainActor (IntentConfirmedAlias) -> Void
    ) -> (QuickCaptureViewModel, MockTextInserter) {
        let speech = MockSpeechCaptureService()
        speech.transcriptToReturn = transcript
        let inserter = MockTextInserter()
        let store = FileCaptureStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("json"))
        let routeProvider: (@MainActor () -> IntentRoutePolicy)?
        if compiler == nil { routeProvider = nil } else { routeProvider = { .injectedCompiler } }
        let vm = QuickCaptureViewModel(
            speech: speech, coach: MockCoachAPI(), store: store, inserter: inserter,
            intentCompiler: compiler,
            intentRoutePolicyProvider: routeProvider,
            intentGroundingProvider: { grounding },
            intentConfirmedAliasSink: sink)
        vm.locale = .chinese
        return (vm, inserter)
    }

    // MARK: - learnable() decision

    @Test func learnable_returnsConfirmedAliasForGroundedEntityInsert() async {
        let proposal = await contestedProposal()
        let clueID = proposal.content.candidates[0].id                 // the "何正杰" candidate
        let outcome = IntentReviewResolver.confirm(candidateID: clueID, in: proposal)

        #expect(outcome == .insertable(text: "何正杰，请转告他", route: .intentPlan))
        #expect(IntentConfirmedAliasLearning.learnable(confirmedCandidateID: clueID, in: proposal, outcome: outcome)
            == IntentConfirmedAlias(surface: "贺正杰", canonical: "何正杰"))
    }

    @Test func learnable_nilWhenOutcomeIsNotInsertable() async {
        let proposal = await contestedProposal()
        let clueID = proposal.content.candidates[0].id
        // Even a real grounded entity id learns nothing if the confirmation did not insert.
        #expect(IntentConfirmedAliasLearning.learnable(
            confirmedCandidateID: clueID, in: proposal, outcome: .needsReview(reason: .compilerRequested)) == nil)
        #expect(IntentConfirmedAliasLearning.learnable(
            confirmedCandidateID: clueID, in: proposal, outcome: .safeUnavailable(reason: .invalidPlan)) == nil)
    }

    @Test func learnable_nilWhenCandidateIsNotAGroundedEntity() async {
        let proposal = await contestedProposal()
        let outcome = IntentReviewResolver.confirm(
            candidateID: proposal.content.candidates[0].id, in: proposal)   // an insertable outcome
        // A candidate id that is not a whitelisted entity (e.g. a correction-chain choice) → nil.
        #expect(IntentConfirmedAliasLearning.learnable(
            confirmedCandidateID: "c-correction", in: proposal, outcome: outcome) == nil)
    }

    @Test func learnable_nilWhenSurfaceEqualsCanonical() {
        // A dictionary normalization whose spoken span already equals the canonical value learns
        // nothing (there is no mishear to repair).
        let unit = IntentSourceSegmenter.segment("PaddleOCR")[0]
        let entity = IntentEntityCandidate(
            id: "entity-0000", value: "PaddleOCR", provenance: .dictionary,
            target: IntentPlanSourceReference(unit))
        let proposal = IntentReviewProposal(
            transcript: "PaddleOCR", sourceUnits: [unit], entityCandidates: [entity])

        #expect(IntentConfirmedAliasLearning.learnable(
            confirmedCandidateID: "entity-0000", in: proposal,
            outcome: .insertable(text: "PaddleOCR", route: .intentPlan)) == nil)
    }

    // MARK: - persistence gate (学习关闭 / 敏感场景 最高优先级)

    @Test func shouldPersist_gatedByLearningToggleAndSensitiveContext() {
        let alias = IntentConfirmedAlias(surface: "贺正杰", canonical: "何正杰")

        // Learning enabled + ordinary app → allowed.
        #expect(IntentConfirmedAliasLearning.shouldPersist(alias, learningEnabled: true, appName: "Notes"))
        // Learning off → never, even on a successful confirm.
        #expect(!IntentConfirmedAliasLearning.shouldPersist(alias, learningEnabled: false, appName: "Notes"))
        // Protected app → never.
        #expect(!IntentConfirmedAliasLearning.shouldPersist(alias, learningEnabled: true, appName: "Terminal"))
        // Sensitive-looking surface/canonical → never.
        #expect(!IntentConfirmedAliasLearning.shouldPersist(
            IntentConfirmedAlias(surface: "sk-ABCDEFGHIJKLMNOP", canonical: "token"),
            learningEnabled: true, appName: "Notes"))
    }

    // MARK: - VM emission

    @Test func confirmingGroundedEntity_emitsConfirmedAliasOnce() async {
        var recorded: [IntentConfirmedAlias] = []
        let (vm, inserter) = makeVM(
            compiler: contestedCompiler(),
            grounding: IntentGroundingSources(aliases: [.init(surface: "贺正杰", canonical: "何政杰")]),
            sink: { recorded.append($0) })

        vm.push(outputMode: .intentAwareDictation)
        await vm.release()
        #expect(vm.phase == .review)                                   // contested → review
        let clueID = try! #require(vm.intentReviewContent?.candidates.first).id
        await vm.confirmIntentCandidate(id: clueID)

        #expect(vm.phase == .idle)
        #expect(inserter.inserted == ["何正杰，请转告他"])
        #expect(recorded == [IntentConfirmedAlias(surface: "贺正杰", canonical: "何正杰")])
    }

    @Test func autoAdoptedUniqueGroundedEntity_neverEmits() async {
        // No competing alias → the spoken clue resolves to a UNIQUE candidate the pipeline
        // auto-adopts. No review, no confirmation → nothing learned (acceptance: 唯一候选自动采用不学习).
        var recorded: [IntentConfirmedAlias] = []
        let (vm, inserter) = makeVM(
            compiler: contestedCompiler(), grounding: .empty, sink: { recorded.append($0) })

        vm.push(outputMode: .intentAwareDictation)
        await vm.release()

        #expect(vm.phase == .idle)
        #expect(inserter.inserted == ["何正杰，请转告他"])
        #expect(recorded.isEmpty)
    }

    @Test func confirmingCorrectionChainCandidate_emitsNothing() async {
        // A correction-chain review confirms and inserts, but its candidates are NOT grounded
        // entities → no alias is learned (acceptance: 模型候选/改口 candidate 不学习).
        var recorded: [IntentConfirmedAlias] = []
        let (vm, inserter) = makeVM(compiler: nil, sink: { recorded.append($0) })
        let transcript = "周三，不对，周四"
        let units = IntentSourceSegmenter.segment(transcript)
        let correctionPlan = IntentPlan(
            version: 1, decision: .render,
            units: [
                .init(source: .init(units[0]), role: .content),
                .init(source: .init(units[1]), role: .correction),
                .init(source: .init(units[2]), role: .content)
            ],
            supersessions: [.init(winner: .init(units[2]), loser: .init(units[0]), cue: .init(units[1]))])
        vm.transcript = transcript
        vm.presentIntentReview(IntentReviewProposal(
            transcript: transcript, sourceUnits: units, sanitizedDraft: "周四",
            candidates: [.init(id: "c-correction", value: "只保留「周四」", evidence: "改口", plan: correctionPlan)],
            forbiddenFragments: ["不对", "周三"]))

        await vm.confirmIntentCandidate(id: "c-correction")

        #expect(vm.phase == .idle)
        #expect(inserter.inserted == ["周四"])          // it DID insert…
        #expect(recorded.isEmpty)                       // …but learned nothing
    }

    @Test func failedReVerificationOnConfirm_emitsNothing() async {
        // Confirm a candidate whose plan selects an unknown entity id → verifier throws →
        // safe-unavailable. A confirmation that did not insert must not learn.
        var recorded: [IntentConfirmedAlias] = []
        let (vm, inserter) = makeVM(compiler: nil, sink: { recorded.append($0) })
        let transcript = "周三，不对，周四"
        let units = IntentSourceSegmenter.segment(transcript)
        let invalidPlan = IntentPlan(
            version: 1, decision: .render,
            units: units.map { .init(source: .init($0), role: .content) },
            supersessions: [], entities: ["entity-9999"])   // no such candidate → verify throws
        vm.transcript = transcript
        vm.presentIntentReview(IntentReviewProposal(
            transcript: transcript, sourceUnits: units,
            candidates: [.init(id: "c-invalid", value: "无效", evidence: "x", plan: invalidPlan)]))

        await vm.confirmIntentCandidate(id: "c-invalid")

        #expect(inserter.inserted.isEmpty)                 // nothing reached the field
        #expect(recorded.isEmpty)                          // and nothing was learned
    }
}
