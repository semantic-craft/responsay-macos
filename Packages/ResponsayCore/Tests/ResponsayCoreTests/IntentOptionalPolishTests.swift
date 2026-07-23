import Foundation
import Testing
@testable import ResponsayCore

// #564 — the optional second-stage polish: it sees ONLY the verified sanitized draft, and its
// output reaches the field only through IntentPostPolishGuard. Every failure mode falls back to
// the sanitized draft — never review-less raw, never unverified polish text.

private func verifiedCorrection() throws -> (verified: IntentPlanVerifier.VerifiedPlan, draft: String) {
    let transcript = "预算是3000元，不对，是5000元"
    let units = IntentSourceSegmenter.segment(transcript)
    let verified = try IntentPlanVerifier.verify(
        IntentPlan(
            version: 1,
            decision: .render,
            units: [
                .init(source: .init(units[0]), role: .content),
                .init(source: .init(units[1]), role: .correction),
                .init(source: .init(units[2]), role: .content)
            ],
            supersessions: [
                .init(winner: .init(units[2]), loser: .init(units[0]), cue: .init(units[1]))
            ]),
        sourceUnits: units,
        transcript: transcript)
    return (verified, TextCorrectionRules.apply(to: IntentSourceRenderer.render(verified).text))
}

@Test func postPolishGuard_acceptsFaithfulSameLanguageTidy() throws {
    let (verified, draft) = try verifiedCorrection()
    #expect(IntentPostPolishGuard.accepts(
        polished: "是5000元。", sanitizedDraft: draft, verified: verified))
}

@Test func postPolishGuard_rejectsMechanicalInvariantViolations() throws {
    let (verified, draft) = try verifiedCorrection()
    let rejected: [(String, String)] = [
        ("digit run reformatted", "是5,000元"),
        ("digit run changed", "是6000元"),
        ("silent translation", "The budget is 5000 yuan"),
        ("superseded content resurfaces", "预算是3000元，最终是5000元"),
        ("correction cue resurfaces", "不对，是5000元"),
        ("emptied out", "   "),
        ("length explosion", String(repeating: "是5000元，", count: 20))
    ]
    for (name, polished) in rejected {
        #expect(!IntentPostPolishGuard.accepts(
            polished: polished, sanitizedDraft: draft, verified: verified), "\(name)")
    }
}

@Test func postPolishGuard_protectsCanonicalEntityValues() throws {
    let transcript = "贺正杰，如何的何、纯正的正、杰出的杰，请转告他"
    let units = IntentSourceSegmenter.segment(transcript)
    let candidates = IntentEntityCandidateTable.build(
        transcript: transcript, units: units, grounding: .empty)
    let verified = try IntentPlanVerifier.verify(
        IntentPlan(
            version: 1,
            decision: .render,
            units: [
                .init(source: .init(units[0]), role: .content),
                .init(source: .init(units[1]), role: .grounding),
                .init(source: .init(units[2]), role: .content)
            ],
            supersessions: [],
            entities: ["entity-0000"]),
        sourceUnits: units,
        transcript: transcript,
        entityCandidates: candidates)
    let draft = TextCorrectionRules.apply(to: IntentSourceRenderer.render(verified).text)

    #expect(IntentPostPolishGuard.accepts(
        polished: "何正杰，请转告他。", sanitizedDraft: draft, verified: verified))
    #expect(!IntentPostPolishGuard.accepts(
        polished: "何政杰，请转告他。", sanitizedDraft: draft, verified: verified))
}

@Test func postPolishGuard_neverPolishesStructuredDrafts() throws {
    let transcript = "第一件事，第二件事"
    let units = IntentSourceSegmenter.segment(transcript)
    let verified = try IntentPlanVerifier.verify(
        IntentPlan(
            version: 1,
            decision: .render,
            units: units.map { .init(source: .init($0), role: .content) },
            supersessions: [],
            structure: IntentPlanStructure(
                kind: .bulletList, groups: [["source-0000"], ["source-0001"]])),
        sourceUnits: units,
        transcript: transcript)
    let draft = IntentSourceRenderer.render(verified).text

    #expect(!IntentPostPolishGuard.accepts(
        polished: "- 第一件事\n- 第二件事", sanitizedDraft: draft, verified: verified))
}

// MARK: - Two-stage pipeline behaviour

private func compileWithPolish(
    _ polish: @escaping @Sendable (String) async throws -> String
) async -> IntentCompilationOutcome {
    let compiler = FixtureIntentCompiler { input in
        let sources = input.sourceUnits
        return try JSONEncoder().encode(IntentPlan(
            version: 1,
            decision: .render,
            units: [
                .init(source: .init(sources[0]), role: .content),
                .init(source: .init(sources[1]), role: .correction),
                .init(source: .init(sources[2]), role: .content)
            ],
            supersessions: [
                .init(winner: .init(sources[2]), loser: .init(sources[0]), cue: .init(sources[1]))
            ]))
    }
    return await IntentCompilationPipeline(compiler: compiler).compile(
        finalTranscript: "预算是3000元，不对，是5000元",
        locale: .chinese,
        allowedContext: nil,
        routePolicy: .injectedCompiler,
        optionalPolish: IntentOptionalPolisher(polish: polish))
}

@Test func optionalPolish_passingGuard_insertsPolishedText() async {
    let outcome = await compileWithPolish { draft in
        // Stage 2 sees the sanitized draft (post correction rules), nothing else.
        #expect(draft == "是 5000 元")
        return "是 5000 元。"
    }
    #expect(outcome == .insertable(text: "是 5000 元。", route: .intentPlan))
}

@Test func optionalPolish_guardFailureOrThrow_fallsBackToSanitizedDraft() async {
    let mangled = await compileWithPolish { _ in "是 5,000 元" }
    #expect(mangled == .insertable(text: "是 5000 元", route: .intentPlan))

    struct PolishDown: Error {}
    let threw = await compileWithPolish { _ in throw PolishDown() }
    #expect(threw == .insertable(text: "是 5000 元", route: .intentPlan))
}

@Test func optionalPolish_appliesToExplicitOrdinaryRouteToo() async {
    let compiler = FixtureIntentCompiler { input in
        try JSONEncoder().encode(IntentPlan(
            version: 1,
            decision: .noIntentControl,
            units: input.sourceUnits.map { .init(source: .init($0), role: .content) },
            supersessions: []))
    }
    let outcome = await IntentCompilationPipeline(compiler: compiler).compile(
        finalTranscript: "今天评审很顺利大家没有意见",
        locale: .chinese,
        allowedContext: nil,
        routePolicy: .injectedCompiler,
        optionalPolish: IntentOptionalPolisher(polish: { _ in "今天评审很顺利，大家没有意见。" }))
    #expect(outcome == .insertable(text: "今天评审很顺利，大家没有意见。", route: .ordinaryPolished))
}
