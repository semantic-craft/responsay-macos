import Foundation
import Testing
@testable import ResponsayCore

/// #567 · S6 — the warm-cloud latency gate, proven with DETERMINISTIC synthetic traces (fixed base
/// date + offsets — no wall clock, reproducible). Real warm-cloud numbers are #568's on-device run;
/// here the gate math, thresholds and the AC8 degradation invariant are what's under test.
struct IntentLatencyGateTests {
    private static let base = Date(timeIntervalSince1970: 1_000_000)

    /// A trace spanning `totalMs`, stamping every stage at a fixed fraction. `includeOptionalPolish`
    /// = false models the allowed latency shedding; `includeSafety` = false models an illegal
    /// safety-stage skip.
    private static func trace(
        totalMs: Double, includeOptionalPolish: Bool = true, includeSafety: Bool = true,
        includeVisible: Bool = true
    ) -> IntentLatencyTrace {
        func at(_ fraction: Double) -> Date { base.addingTimeInterval(totalMs * fraction / 1000) }
        var t = IntentLatencyTrace()
        t.mark(.stop, at: base)
        t.mark(.compile, at: at(0.4))
        if includeSafety {
            t.mark(.planVerify, at: at(0.5))
            t.mark(.sourceRender, at: at(0.6))
        }
        if includeOptionalPolish { t.mark(.optionalPolish, at: at(0.8)) }
        if includeSafety { t.mark(.postRenderGuard, at: at(0.9)) }
        if includeVisible { t.mark(.visible, at: at(1.0)) }
        return t
    }

    private static func warmCloud(_ totals: [Double]) -> [IntentLatencyTrace] {
        totals.map { trace(totalMs: $0) }
    }

    /// Date arithmetic makes stop→visible ms land within a rounding hair of the integer target.
    private static func close(_ actual: Double?, _ expected: Double, eps: Double = 0.01) -> Bool {
        guard let actual else { return false }
        return abs(actual - expected) < eps
    }

    @Test func withinBudgetAndRegressionPasses() {
        let verdict = IntentLatencyGate.evaluate(
            warmCloud: Self.warmCloud([1200, 1400, 1500, 1600, 1800]),
            polishedBaselineP95Ms: 2000)
        #expect(Self.close(verdict.p50Ms, 1500))
        #expect(Self.close(verdict.p95Ms, 1800))
        #expect(Self.close(verdict.regression, 1800.0 / 2000.0 - 1))
        #expect(verdict.allSafetyStagesPresent)
        #expect(verdict.passed)
        // per-stage percentiles are reported for diagnosis (compile/planVerify/.../postRenderGuard).
        #expect(verdict.stagePercentilesMs["compile"] != nil)
        #expect(verdict.stagePercentilesMs["postRenderGuard"] != nil)
    }

    @Test func p95OverBudgetFails() {
        let verdict = IntentLatencyGate.evaluate(
            warmCloud: Self.warmCloud([1400, 1500, 1600, 1800, 6000]),   // p95 = 6000 > 5000
            polishedBaselineP95Ms: 6000)
        #expect(Self.close(verdict.p95Ms, 6000))
        #expect(!verdict.passed)
    }

    @Test func regressionOverToleranceFailsEvenWhenAbsolutelyFast() {
        // Absolute p50/p95 are well within budget, but > 25% slower than Polished p95 → fail.
        let verdict = IntentLatencyGate.evaluate(
            warmCloud: Self.warmCloud([1700, 1750, 1800, 1850, 1900]),
            polishedBaselineP95Ms: 1000)
        #expect(Self.close(verdict.p95Ms, 1900))
        #expect((verdict.regression ?? 0) > 0.25)
        #expect(!verdict.passed)
    }

    @Test func shedOptionalPolishStillPassesWhenSafetyStagesRemain() {
        // AC8: dropping optional polish under latency pressure is allowed and stays safe.
        let degraded = [1300, 1400, 1500].map { Self.trace(totalMs: $0, includeOptionalPolish: false) }
        let verdict = IntentLatencyGate.evaluate(warmCloud: degraded, polishedBaselineP95Ms: 2000)
        #expect(verdict.allSafetyStagesPresent)
        #expect(verdict.passed)
        #expect(verdict.stagePercentilesMs["optionalPolish"] == nil)   // shed → not measured
    }

    @Test func skippingASafetyStageFailsEvenWhenFast() {
        // AC8: latency shedding may NOT skip plan verify / source render / post-render guard.
        var traces = Self.warmCloud([1300, 1400])
        traces.append(Self.trace(totalMs: 1350, includeSafety: false))   // unsafe shortcut
        let verdict = IntentLatencyGate.evaluate(warmCloud: traces, polishedBaselineP95Ms: 2000)
        #expect(!verdict.allSafetyStagesPresent)
        #expect(!verdict.passed, "a fast-but-unsafe shortcut must fail the gate")
    }

    @Test func noVisibleSamplesDoNotSilentlyPass() {
        let noVisible = [1200, 1300].map { Self.trace(totalMs: $0, includeVisible: false) }
        let verdict = IntentLatencyGate.evaluate(warmCloud: noVisible, polishedBaselineP95Ms: 2000)
        #expect(verdict.sampleCount == 0)
        #expect(verdict.p95Ms == nil)
        #expect(!verdict.passed)
    }

    @Test func presentStageDurationsSumToStopToVisible() {
        let t = Self.trace(totalMs: 2000)
        let stages: [IntentLatencyTrace.Stage] = [.compile, .planVerify, .sourceRender, .optionalPolish, .postRenderGuard, .visible]
        let sum = stages.compactMap { t.durationMs(to: $0) }.reduce(0, +)
        #expect(abs(sum - (t.stopToVisibleMs ?? 0)) < 0.0001)
    }

    @Test func coldLocalReportedSeparatelyNotGatedWithWarm() {
        let cold = Self.warmCloud([3000, 3500, 4000])
        let report = IntentLatencyGate.coldLocalReport(cold)
        #expect(Self.close(report?.p50Ms, 3500))
        #expect(Self.close(report?.p95Ms, 4000))
    }
}
