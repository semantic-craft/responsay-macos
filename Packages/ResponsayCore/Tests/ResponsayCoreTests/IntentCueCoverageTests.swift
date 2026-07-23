import Foundation
import Testing
@testable import ResponsayCore

// #561 — the preflight VETO (spec decision 22): when the raw utterance obviously contains a
// correction or side-note cue that the verified plan does not explain (the flagged unit is not
// classified as correction / sideNote), the capture must stop in needs-review. The veto is
// one-directional: a preflight miss never authorizes anything — compiler absence, bad structure
// and verifier rejection keep their safe-unavailable outcomes regardless of preflight.

private func compile(
    _ transcript: String,
    plan: @escaping @Sendable ([IntentSourceUnit]) -> IntentPlan
) async -> IntentCompilationOutcome {
    let compiler = FixtureIntentCompiler { input in
        try JSONEncoder().encode(plan(input.sourceUnits))
    }
    return await IntentCompilationPipeline(compiler: compiler).compile(
        finalTranscript: transcript,
        locale: .chinese,
        allowedContext: nil,
        routePolicy: .injectedCompiler)
}

@Test func unexplainedCorrectionCue_vetoesNoIntentControlPlan() async {
    let outcome = await compile("周三开会，不对，周四开会") { sources in
        IntentPlan(
            version: 1,
            decision: .noIntentControl,
            units: sources.map { .init(source: .init($0), role: .content) },
            supersessions: [])
    }
    #expect(outcome == .needsReview(reason: .unexplainedCorrectionCue))
}

@Test func unexplainedSideNoteCue_vetoesAllContentRenderPlan() async {
    let outcome = await compile("帮我谢谢小王，这句不用写，他帮了大忙") { sources in
        IntentPlan(
            version: 1,
            decision: .render,
            units: sources.map { .init(source: .init($0), role: .content) },
            supersessions: [])
    }
    #expect(outcome == .needsReview(reason: .unexplainedSideNoteCue))
}

@Test func bothCueKindsUnexplained_correctionReasonWins() async {
    let outcome = await compile("周三交，不对，周五交，这句不用写") { sources in
        IntentPlan(
            version: 1,
            decision: .noIntentControl,
            units: sources.map { .init(source: .init($0), role: .content) },
            supersessions: [])
    }
    #expect(outcome == .needsReview(reason: .unexplainedCorrectionCue))
}

@Test func explainedCues_doNotTriggerTheVeto() async {
    // Correction cue resolved into a supersession + side note marked sideNote → auto-insert,
    // with the loser, the cue, and the note all excluded from the final text.
    let outcome = await compile("周三交稿，不对，周五交稿，这句不用写") { sources in
        IntentPlan(
            version: 1,
            decision: .render,
            units: [
                .init(source: .init(sources[0]), role: .content),
                .init(source: .init(sources[1]), role: .correction),
                .init(source: .init(sources[2]), role: .content),
                .init(source: .init(sources[3]), role: .sideNote)
            ],
            supersessions: [
                .init(winner: .init(sources[2]), loser: .init(sources[0]), cue: .init(sources[1]))
            ])
    }
    #expect(outcome == .insertable(text: "周五交稿，", route: .intentPlan))
}

@Test func quotedCue_doesNotVetoNoIntentControl() async {
    // 引号里的“我是说”是被引用的内容，preflight 不命中 → 合法 noIntentControl 照常自动走普通整理。
    let transcript = "他当时说“我是说周四”，后来也没改"
    let outcome = await compile(transcript) { sources in
        IntentPlan(
            version: 1,
            decision: .noIntentControl,
            units: sources.map { .init(source: .init($0), role: .content) },
            supersessions: [])
    }
    #expect(outcome == .insertable(text: transcript, route: .ordinaryPolished))
}

@Test func preflightMiss_neverAuthorizes_compilerFailureStaysSafeUnavailable() async {
    // "有 cue 但编译器坏了" 和 "无 cue 但编译器坏了" 都必须 safe-unavailable —— preflight 未命中
    // 不是自动回退授权 (spec decision 22)。
    struct FailingCompiler: IntentPlanCompiler {
        func compile(_ input: IntentCompilerInput) async throws -> Data {
            throw URLError(.cannotConnectToHost)
        }
    }
    for transcript in ["周三开会，不对，周四开会", "周四开会，请大家准时"] {
        let outcome = await IntentCompilationPipeline(compiler: FailingCompiler()).compile(
            finalTranscript: transcript,
            locale: .chinese,
            allowedContext: nil,
            routePolicy: .injectedCompiler)
        #expect(outcome == .safeUnavailable(reason: .compilerFailed), "\(transcript)")
    }
}

@Test func reviewConfirm_humanConfirmationResolvesTheCue_noSecondVeto() {
    // The veto's job is to route a doubtful cue INTO review — a human confirming a candidate
    // there IS the resolution. Re-vetoing the confirmed plan would livelock the capsule
    // (confirm → review → confirm) and overrule the user on whether 「不对」 was content.
    // Structural safety is untouched: confirm still re-runs verifier + render + guard (#559).
    let transcript = "周三开会，不对，周四开会"
    let units = IntentSourceSegmenter.segment(transcript)
    let keepEverythingPlan = IntentPlan(
        version: 1,
        decision: .render,
        units: units.map { .init(source: .init($0), role: .content) },
        supersessions: [])
    let proposal = IntentReviewProposal(
        transcript: transcript,
        sourceUnits: units,
        candidates: [.init(id: "c1", value: "两者都写", evidence: "并列", plan: keepEverythingPlan)])

    let outcome = IntentReviewResolver.confirm(candidateID: "c1", in: proposal)

    #expect(outcome == .insertable(text: transcript, route: .intentPlan))
}
