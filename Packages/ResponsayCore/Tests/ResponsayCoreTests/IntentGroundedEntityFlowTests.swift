import Foundation
import Testing
@testable import ResponsayCore

// #562 — the grounded-entity flow end to end: 口述释字 resolves through the generic
// candidate/provenance chain (no name-specific code anywhere), contested slots stop in review
// with keyboard-confirmable candidates that re-run the full verifier + guard, and a compiler
// that tries to freestyle an entity has no representable way to do it.

private func compileGrounded(
    _ transcript: String,
    grounding: IntentGroundingSources = .empty,
    plan: @escaping @Sendable (IntentCompilerInput) -> IntentPlan
) async -> IntentCompilationOutcome {
    let compiler = FixtureIntentCompiler { input in
        try JSONEncoder().encode(plan(input))
    }
    return await IntentCompilationPipeline(compiler: compiler).compile(
        finalTranscript: transcript,
        locale: .chinese,
        allowedContext: nil,
        routePolicy: .injectedCompiler,
        grounding: grounding)
}

/// The canonical 释字 shape: misheard name + clue clause + trailing content.
private let clueTranscript = "贺正杰，如何的何、纯正的正、杰出的杰，请转告他"

private func cluePlan(_ input: IntentCompilerInput, entities: [String]) -> IntentPlan {
    IntentPlan(
        version: 1,
        decision: .render,
        units: [
            .init(source: .init(input.sourceUnits[0]), role: .content),
            .init(source: .init(input.sourceUnits[1]), role: .grounding),
            .init(source: .init(input.sourceUnits[2]), role: .content)
        ],
        supersessions: [],
        entities: entities)
}

@Test func groundedEntity_spokenClueResolvesAndInsertsCanonicalName() async {
    let outcome = await compileGrounded(clueTranscript) { input in
        // The compiler sees the pre-numbered whitelist and selects by ID only.
        #expect(input.entityCandidates.map(\.value) == ["何正杰"])
        return cluePlan(input, entities: [input.entityCandidates[0].id])
    }
    #expect(outcome == .insertable(text: "何正杰，请转告他", route: .intentPlan))
}

@Test func groundedEntity_contestedSlotStopsInReview_confirmReVerifiesEitherWay() async {
    // A contrived confirmed alias proves a DIFFERENT spelling for the same misheard span →
    // 唯一或弃权: the pipeline must not silently pick a side.
    let grounding = IntentGroundingSources(
        aliases: [.init(surface: "贺正杰", canonical: "何政杰")])
    let outcome = await compileGrounded(clueTranscript, grounding: grounding) { input in
        cluePlan(input, entities: [input.entityCandidates[0].id])
    }

    guard case let .needsReview(reason, proposal?) = outcome else {
        Issue.record("expected contested-entity review, got \(outcome)")
        return
    }
    #expect(reason == .ambiguousEntityCandidates)
    #expect(proposal.content.candidates.map(\.value) == ["何正杰", "何政杰"])
    #expect(proposal.content.candidates.map(\.evidence) == ["口述释字", "已确认别名"])
    // The safe draft leaves the contested span exactly as spoken, clue units excluded.
    #expect(proposal.content.sanitizedDraft == "贺正杰，请转告他")

    // Keyboard-confirm either candidate → verifier + render + guard again → insertable.
    let confirmClue = IntentReviewResolver.confirm(
        candidateID: proposal.content.candidates[0].id, in: proposal)
    #expect(confirmClue == .insertable(text: "何正杰，请转告他", route: .intentPlan))
    let confirmAlias = IntentReviewResolver.confirm(
        candidateID: proposal.content.candidates[1].id, in: proposal)
    #expect(confirmAlias == .insertable(text: "何政杰，请转告他", route: .intentPlan))

    // The clue clause is control speech — an edited draft may not smuggle it back in.
    #expect(IntentReviewResolver.submit(
        editedDraft: "如何的何、纯正的正、杰出的杰", in: proposal)
        == .needsReview(reason: .compilerRequested))
}

@Test func groundedEntity_planIgnoringClueUnits_isVetoedIntoReview() async {
    // The plan pretends the clue clause is ordinary prose → preflight grounding cue unexplained.
    let outcome = await compileGrounded(clueTranscript) { input in
        IntentPlan(
            version: 1,
            decision: .noIntentControl,
            units: input.sourceUnits.map { .init(source: .init($0), role: .content) },
            supersessions: [])
    }
    #expect(outcome == .needsReview(reason: .unexplainedGroundingCue))
}

@Test func groundedEntity_freestyleOrUnresolvedEntities_neverInsert() async {
    // Unknown candidate ID — the only way to "invent" a name — is structurally invalid.
    let unknownID = await compileGrounded(clueTranscript) { input in
        cluePlan(input, entities: ["entity-9999"])
    }
    #expect(unknownID == .safeUnavailable(reason: .invalidPlan))

    // Grounding units acknowledged but nothing resolved on a render decision (#575): with a
    // non-empty table this is now a candidate-confirm review — still never a silent
    // wrong-name insert, but recoverable with one tap instead of a dead blocked card.
    let unresolved = await compileGrounded(clueTranscript) { input in
        cluePlan(input, entities: [])
    }
    guard case let .needsReview(unresolvedReason, unresolvedProposal) = unresolved else {
        Issue.record("expected candidate-confirm review, got \(unresolved)")
        return
    }
    #expect(unresolvedReason == .unexplainedGroundingCue)
    #expect(unresolvedProposal?.candidates.isEmpty == false)

    // The correct abstention (zero usable candidates) is decision needsReview → review.
    let abstained = await compileGrounded(clueTranscript) { input in
        IntentPlan(
            version: 1,
            decision: .needsReview,
            units: [
                .init(source: .init(input.sourceUnits[0]), role: .content),
                .init(source: .init(input.sourceUnits[1]), role: .grounding),
                .init(source: .init(input.sourceUnits[2]), role: .content)
            ],
            supersessions: [])
    }
    #expect(abstained == .needsReview(reason: .compilerRequested))
}

@Test func groundedEntity_mixedLanguageDictionaryNormalization_endToEnd() async {
    let outcome = await compileGrounded(
        "把 paddleocr 的识别结果发给 Kevin，谢谢",
        grounding: IntentGroundingSources(dictionaryTerms: ["PaddleOCR"])
    ) { input in
        #expect(input.entityCandidates.map(\.value) == ["PaddleOCR"])
        return IntentPlan(
            version: 1,
            decision: .render,
            units: input.sourceUnits.map { .init(source: .init($0), role: .content) },
            supersessions: [],
            entities: [input.entityCandidates[0].id])
    }
    #expect(outcome == .insertable(text: "把 PaddleOCR 的识别结果发给 Kevin，谢谢", route: .intentPlan))
}
