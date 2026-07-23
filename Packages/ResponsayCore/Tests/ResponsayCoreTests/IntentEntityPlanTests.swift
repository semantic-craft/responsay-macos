import Foundation
import Testing
@testable import ResponsayCore

// #562 — plan-level entity selection: the compiler returns candidate IDs only; the verifier
// resolves them against the app-built whitelist and the deterministic renderer splices the
// canonical values. Free-form entity text has no representation at all.

private struct EntityFixture {
    let transcript: String
    let units: [IntentSourceUnit]
    let candidates: [IntentEntityCandidate]

    init(_ transcript: String, grounding: IntentGroundingSources = .empty) {
        self.transcript = transcript
        self.units = IntentSourceSegmenter.segment(transcript)
        self.candidates = IntentEntityCandidateTable.build(
            transcript: transcript, units: units, grounding: grounding)
    }

    func verify(_ plan: IntentPlan) throws -> IntentPlanVerifier.VerifiedPlan {
        try IntentPlanVerifier.verify(
            plan, sourceUnits: units, transcript: transcript, entityCandidates: candidates)
    }
}

@Test func entityPlan_decodesSelectionAndDefaultsToEmpty() throws {
    let withEntities = #"{"version":1,"decision":"render","units":[{"source":{"sourceID":"source-0000","range":{"location":0,"length":1},"exactQuote":"A"},"role":"content"}],"supersessions":[],"entities":["entity-0000"]}"#
    #expect(try JSONDecoder().decode(IntentPlan.self, from: Data(withEntities.utf8)).entities == ["entity-0000"])

    let without = #"{"version":1,"decision":"render","units":[{"source":{"sourceID":"source-0000","range":{"location":0,"length":1},"exactQuote":"A"},"role":"content"}],"supersessions":[]}"#
    #expect(try JSONDecoder().decode(IntentPlan.self, from: Data(without.utf8)).entities.isEmpty)
}

@Test func entityRender_splicesCanonicalValueOverMisheardSpan() throws {
    let fixture = EntityFixture("贺正杰，如何的何、纯正的正、杰出的杰，请转告他")
    let verified = try fixture.verify(IntentPlan(
        version: 1,
        decision: .render,
        units: [
            .init(source: .init(fixture.units[0]), role: .content),
            .init(source: .init(fixture.units[1]), role: .grounding),
            .init(source: .init(fixture.units[2]), role: .content)
        ],
        supersessions: [],
        entities: ["entity-0000"]))

    let draft = IntentSourceRenderer.render(verified)
    #expect(draft.text == "何正杰，请转告他")
    #expect(draft.sourceIDs == ["source-0000", "source-0002"])

    let finalText = TextCorrectionRules.apply(to: draft.text)
    #expect(IntentPostRenderGuard.accepts(draft: draft, finalText: finalText, verified: verified))
}

@Test func entitySelection_unknownDuplicateOrDeadSlotIsInvalid() throws {
    let fixture = EntityFixture("贺正杰，如何的何、纯正的正、杰出的杰，请转告他")
    func plan(entities: [String], groundingRole: IntentSourceRole = .grounding) -> IntentPlan {
        IntentPlan(
            version: 1,
            decision: .render,
            units: [
                .init(source: .init(fixture.units[0]), role: .content),
                .init(source: .init(fixture.units[1]), role: groundingRole),
                .init(source: .init(fixture.units[2]), role: .content)
            ],
            supersessions: [],
            entities: entities)
    }

    #expect(throws: IntentPlanVerifier.VerificationError.self) {
        try fixture.verify(plan(entities: ["entity-9999"]))                    // unknown ID
    }
    #expect(throws: IntentPlanVerifier.VerificationError.self) {
        try fixture.verify(plan(entities: ["entity-0000", "entity-0000"]))     // duplicate
    }

    // Slot inside a unit that never renders: mark the slot's own unit sideNote → invalid.
    let deadSlot = IntentPlan(
        version: 1,
        decision: .render,
        units: [
            .init(source: .init(fixture.units[0]), role: .sideNote),
            .init(source: .init(fixture.units[1]), role: .grounding),
            .init(source: .init(fixture.units[2]), role: .content)
        ],
        supersessions: [],
        entities: ["entity-0000"])
    #expect(throws: IntentPlanVerifier.VerificationError.self) {
        try fixture.verify(deadSlot)
    }
}

@Test func entitySelection_noIntentControlMustCarryNoEntities() throws {
    let fixture = EntityFixture(
        "把 paddleocr 的识别结果发我",
        grounding: IntentGroundingSources(dictionaryTerms: ["PaddleOCR"]))
    let plan = IntentPlan(
        version: 1,
        decision: .noIntentControl,
        units: fixture.units.map { .init(source: .init($0), role: .content) },
        supersessions: [],
        entities: ["entity-0000"])
    #expect(throws: IntentPlanVerifier.VerificationError.self) {
        try fixture.verify(plan)
    }
}

@Test func entityRender_dictionaryNormalizationInsideOrdinarySentence() throws {
    let fixture = EntityFixture(
        "把 paddleocr 的识别结果发我，谢谢",
        grounding: IntentGroundingSources(dictionaryTerms: ["PaddleOCR"]))
    let verified = try fixture.verify(IntentPlan(
        version: 1,
        decision: .render,
        units: fixture.units.map { .init(source: .init($0), role: .content) },
        supersessions: [],
        entities: ["entity-0000"]))

    let draft = IntentSourceRenderer.render(verified)
    #expect(draft.text == "把 PaddleOCR 的识别结果发我，谢谢")

    let finalText = TextCorrectionRules.apply(to: draft.text)
    #expect(IntentPostRenderGuard.accepts(draft: draft, finalText: finalText, verified: verified))
}
