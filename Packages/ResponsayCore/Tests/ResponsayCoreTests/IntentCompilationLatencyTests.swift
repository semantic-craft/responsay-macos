import Foundation
import Testing
@testable import ResponsayCore

/// #568 — the compiler-stage half of the warm-cloud latency trace. `compileTraced` stamps the
/// stages it actually reaches; the VM adds `stop`/`visible` around it. A deterministic stepping
/// clock makes the per-stage decomposition exact and the "not reached ⇒ not stamped" invariant
/// (so a non-insert outcome can never count as a warm sample) provable offline.
private final class SteppingClock: @unchecked Sendable {
    private let base: Date
    private let stepMs: Double
    private var count = 0
    private let lock = NSLock()

    init(base: Date, stepMs: Double) { self.base = base; self.stepMs = stepMs }

    /// Each call advances one fixed step, so `now()` #n = base + n·stepMs.
    func next() -> Date {
        lock.lock(); defer { lock.unlock() }
        let stamp = base.addingTimeInterval(Double(count) * stepMs / 1000)
        count += 1
        return stamp
    }
}

/// Per-stage gaps are reconstructed via `Date` arithmetic, so compare with a small tolerance
/// (accumulated floating-point drift makes an exact 100.0 unrealistic; the 0ms adjacent-mark gap
/// is exact because those two marks share the same `Date` instant).
private func isNear(_ value: Double?, _ target: Double, tol: Double = 0.5) -> Bool {
    guard let value else { return false }
    return abs(value - target) <= tol
}

private func nearbyCorrectionCompiler() -> FixtureIntentCompiler {
    FixtureIntentCompiler { input in
        let sources = input.sourceUnits
        let plan = IntentPlan(
            version: 1,
            decision: .render,
            units: [
                .init(source: .init(sources[0]), role: .content),
                .init(source: .init(sources[1]), role: .correction),
                .init(source: .init(sources[2]), role: .content)
            ],
            supersessions: [
                .init(winner: .init(sources[2]), loser: .init(sources[0]), cue: .init(sources[1]))
            ])
        return try JSONEncoder().encode(plan)
    }
}

@Test func compileTraced_stampsSafetyStagesForInsertable_noOptionalPolish() async {
    let clock = SteppingClock(base: Date(timeIntervalSince1970: 1_000), stepMs: 100)
    let pipeline = IntentCompilationPipeline(compiler: nearbyCorrectionCompiler(), now: clock.next)

    let (outcome, trace) = await pipeline.compileTraced(
        finalTranscript: "周三开会，不对，周四开会",
        locale: .chinese,
        allowedContext: nil,
        routePolicy: .injectedCompiler)

    #expect(outcome == .insertable(text: "周四开会", route: .intentPlan))
    // Compile + verify + render + post-render guard were reached; optional polish was NOT run.
    #expect(trace.marks[.compile] != nil)
    #expect(trace.marks[.planVerify] != nil)
    #expect(trace.marks[.sourceRender] != nil)
    #expect(trace.marks[.postRenderGuard] != nil)
    #expect(trace.marks[.optionalPolish] == nil)
    #expect(trace.safetyStagesPresent)
    // stop/visible are the VM's boundaries — never stamped by the pipeline.
    #expect(trace.marks[.stop] == nil)
    #expect(trace.marks[.visible] == nil)
    #expect(trace.stopToVisibleMs == nil)
    // compile #0, planVerify #1, then render+guard share the finalize instant (#2): a shed optional
    // polish leaves the two safety marks adjacent (0ms gap).
    #expect(isNear(trace.durationMs(to: .planVerify), 100))
    #expect(isNear(trace.durationMs(to: .sourceRender), 100))
    #expect(trace.durationMs(to: .postRenderGuard) == 0)
}

@Test func compileTraced_stampsOptionalPolishBetweenRenderAndFinalGuard() async {
    let clock = SteppingClock(base: Date(timeIntervalSince1970: 2_000), stepMs: 100)
    let pipeline = IntentCompilationPipeline(compiler: nearbyCorrectionCompiler(), now: clock.next)
    // Identity polish → the post-polish guard accepts it (no change is always safe).
    let polisher = IntentOptionalPolisher(polish: { $0 })

    let (outcome, trace) = await pipeline.compileTraced(
        finalTranscript: "周三开会，不对，周四开会",
        locale: .chinese,
        allowedContext: nil,
        routePolicy: .injectedCompiler,
        optionalPolish: polisher)

    #expect(outcome == .insertable(text: "周四开会", route: .intentPlan))
    #expect(trace.marks[.optionalPolish] != nil)
    #expect(trace.safetyStagesPresent)
    // Chronological order holds: sourceRender (#2) ≤ optionalPolish (#3) ≤ postRenderGuard (#4),
    // so summing the present gaps still reconstructs a stop→visible total exactly.
    let render = try? #require(trace.marks[.sourceRender])
    let polish = try? #require(trace.marks[.optionalPolish])
    let guardMark = try? #require(trace.marks[.postRenderGuard])
    #expect(render! <= polish!)
    #expect(polish! <= guardMark!)
    #expect(isNear(trace.durationMs(to: .optionalPolish), 100))
    #expect(isNear(trace.durationMs(to: .postRenderGuard), 100))
}

@Test func compileTraced_leavesSafetyStagesUnstampedForNonInsertOutcomes() async {
    let clock = SteppingClock(base: Date(timeIntervalSince1970: 3_000), stepMs: 100)
    // Invalid plan → verify throws before its mark; a needsReview plan → finalize returns review.
    let invalidPlan = IntentCompilationPipeline(
        compiler: FixtureIntentCompiler { _ in Data("plain text".utf8) }, now: clock.next)
    let needsReview = IntentCompilationPipeline(
        compiler: FixtureIntentCompiler { _ in
            Data(#"{"version":1,"decision":"needsReview","units":[{"source":{"sourceID":"source-0000","range":{"location":0,"length":1},"exactQuote":"A"},"role":"content"}],"supersessions":[]}"#.utf8)
        }, now: clock.next)

    let (invalidOutcome, invalidTrace) = await invalidPlan.compileTraced(
        finalTranscript: "A", locale: .english, allowedContext: nil, routePolicy: .injectedCompiler)
    let (reviewOutcome, reviewTrace) = await needsReview.compileTraced(
        finalTranscript: "A", locale: .english, allowedContext: nil, routePolicy: .injectedCompiler)

    #expect(invalidOutcome == .safeUnavailable(reason: .invalidPlan))
    #expect(!invalidTrace.safetyStagesPresent)          // never a warm sample
    #expect(invalidTrace.marks[.sourceRender] == nil)
    #expect(invalidTrace.marks[.postRenderGuard] == nil)

    #expect(reviewOutcome == .needsReview(reason: .compilerRequested))
    #expect(!reviewTrace.safetyStagesPresent)
    #expect(reviewTrace.marks[.sourceRender] == nil)
}

@Test func intentPipelineDiagnosticEvent_isNumericOnly_andNilForIncompleteTrace() {
    let base = Date(timeIntervalSince1970: 5_000)
    var complete = IntentLatencyTrace()
    complete.mark(.stop, at: base)
    complete.mark(.compile, at: base.addingTimeInterval(1.8))
    complete.mark(.planVerify, at: base.addingTimeInterval(1.81))
    complete.mark(.sourceRender, at: base.addingTimeInterval(1.82))
    complete.mark(.postRenderGuard, at: base.addingTimeInterval(1.82))
    complete.mark(.visible, at: base.addingTimeInterval(1.9))

    let event = DiagnosticEvent.intentPipeline(
        complete, route: "intentPlan", provider: "cloud", timestamp: base)
    let unwrapped = try? #require(event)
    #expect(unwrapped?.category == .pipeline)
    #expect(unwrapped?.fields["totalMs"] == "1900")
    #expect(unwrapped?.fields["safetyStagesPresent"] == "1")
    #expect(unwrapped?.fields["route"] == "intentPlan")
    // Numeric ms + labels only — no raw draft/transcript/plan may ride the diagnostics feed.
    let joined = (unwrapped?.fields.values.joined(separator: " ") ?? "") + " " + (unwrapped?.title ?? "")
    #expect(!joined.contains("周"))

    // An incomplete trace (no visible) is not a warm sample → no event.
    var incomplete = IntentLatencyTrace()
    incomplete.mark(.stop, at: base)
    incomplete.mark(.compile, at: base.addingTimeInterval(1.8))
    #expect(DiagnosticEvent.intentPipeline(
        incomplete, route: nil, provider: nil, timestamp: base) == nil)
}
