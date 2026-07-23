import Foundation
import Testing
@testable import ResponsayCore

/// #567 · S5 — the opt-in provider contract runner (Testing Decision 16 / AC6 / AC11).
/// The OFFLINE tests prove the runner + gate deterministically with ZERO network (stub compilers).
/// The LIVE tests are gated on real credentials in the environment; when absent they are SKIPPED
/// (reported as NOT RUN — never a faked pass).
struct IntentProviderContractRunnerTests {

    private typealias Runner = IntentProviderContractRunner

    /// A compliant provider: returns a verifier-valid noIntentControl plan for any input.
    private static let compliantStub = FixtureIntentCompiler { input in
        try JSONEncoder().encode(IntentPlan(
            version: 1, decision: .noIntentControl,
            units: input.sourceUnits.map { .init(source: .init($0), role: .content) },
            supersessions: []))
    }

    /// A hostile provider: returns free text (no plan JSON) for every request.
    private static let plainTextStub = FixtureIntentCompiler { _ in Data("周四开会，就这样".utf8) }

    // MARK: - Offline determinism (zero network)

    @Test func compliantProviderPassesTheContractGate() async {
        let requests = (0..<100).map { _ in Runner.Request(transcript: "今天进展顺利，明天继续推进") }
        let tally = await Runner.run(compiler: Self.compliantStub, requests: requests)

        #expect(tally == .init(insertable: 100, needsReview: 0, safeUnavailable: 0, total: 100))
        #expect(tally.structuralValidRate == 1.0)
        #expect(Runner.passesGate(tally))
    }

    @Test func plainTextResponsesNeverPassThroughToInsertion() async {
        let requests = (0..<100).map { _ in Runner.Request(transcript: "把材料发出去") }
        let tally = await Runner.run(compiler: Self.plainTextStub, requests: requests)

        // The hard safety property, directly measured: free provider text reaches insertion ZERO
        // times — every plain-text response is rejected into safe-unavailable, never auto-inserted.
        #expect(tally.insertable == 0)
        #expect(tally.safeUnavailable == 100)
        #expect(!Runner.passesGate(tally))   // a non-compliant provider must fail the gate
    }

    @Test func nonCompliantProviderFailsGateButEveryMissStaysSafe() async {
        // 5 of 100 requests carry an obvious correction cue the stub leaves unexplained → the
        // pipeline vetoes them into safe review (never a wrong auto-insert). 95 cue-free → insert.
        let requests = (0..<100).map { index in
            Runner.Request(transcript: index < 5 ? "改到周四，不对，周五" : "今天进展顺利，明天继续推进")
        }
        let tally = await Runner.run(compiler: Self.compliantStub, requests: requests)

        #expect(tally.insertable == 95)
        #expect(tally.needsReview == 5)                 // misses stayed SAFE (review), not inserted
        #expect(tally.safeUnavailable == 0)
        #expect(tally.insertable + tally.safeRest == tally.total)
        #expect(tally.structuralValidRate == 0.95)
        #expect(!Runner.passesGate(tally), "0.95 < 0.99 must fail the gate")
    }

    @Test func emptyBatchIsNotSilentlyPassing() {
        let empty = Runner.Tally(insertable: 0, needsReview: 0, safeUnavailable: 0, total: 0)
        #expect(!Runner.passesGate(empty))
    }

}
