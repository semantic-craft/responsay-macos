import Foundation

/// #567 — the warm-cloud latency gate (Testing Decision 17 / AC7 / AC8). Pure percentile math over
/// `IntentLatencyTrace` samples (reusing `LatencyStats`), so the gate LOGIC + thresholds + the
/// degradation invariant are proven offline with synthetic fixed-date samples; real warm-cloud
/// numbers arrive from #568's on-device run. Cold-local is reported separately, never gated with
/// warm-cloud.
public enum IntentLatencyGate {
    public struct Thresholds: Sendable, Equatable {
        public let p50MaxMs: Double
        public let p95MaxMs: Double
        public let maxRegression: Double

        public init(p50MaxMs: Double = 2000, p95MaxMs: Double = 5000, maxRegression: Double = 0.25) {
            self.p50MaxMs = p50MaxMs
            self.p95MaxMs = p95MaxMs
            self.maxRegression = maxRegression
        }
    }

    public struct StagePercentile: Sendable, Equatable {
        public let p50Ms: Double
        public let p95Ms: Double
    }

    public struct Verdict: Sendable, Equatable {
        public let sampleCount: Int
        public let p50Ms: Double?
        public let p95Ms: Double?
        public let polishedBaselineP95Ms: Double
        /// (warm p95 / Polished p95) − 1; nil when there are no samples or no baseline.
        public let regression: Double?
        /// AC8: every sample stamped the non-skippable safety stages (optional polish may be shed).
        public let allSafetyStagesPresent: Bool
        public let passed: Bool
        /// Per-stage p50/p95 for the report (compile / planVerify / sourceRender / optionalPolish /
        /// postRenderGuard), keyed by `IntentLatencyTrace.Stage.rawValue`.
        public let stagePercentilesMs: [String: StagePercentile]
    }

    /// Gate the warm default-cloud route. Passes only when there is at least one sample, p50/p95 are
    /// within budget, the regression vs current Polished p95 is within tolerance, AND no sample
    /// skipped a safety stage (a fast-but-unsafe shortcut fails even if the numbers are green).
    public static func evaluate(
        warmCloud: [IntentLatencyTrace],
        polishedBaselineP95Ms: Double,
        thresholds: Thresholds = Thresholds()
    ) -> Verdict {
        let samples = warmCloud.compactMap { $0.stopToVisibleMs }
        let p50 = LatencyStats.percentile(samples, 50)
        let p95 = LatencyStats.percentile(samples, 95)
        let regression: Double? = (p95 != nil && polishedBaselineP95Ms > 0)
            ? (p95! / polishedBaselineP95Ms - 1) : nil
        let safety = warmCloud.allSatisfy { $0.safetyStagesPresent }

        let withinBudget = (p50 != nil && p50! <= thresholds.p50MaxMs)
            && (p95 != nil && p95! <= thresholds.p95MaxMs)
            && (regression != nil && regression! <= thresholds.maxRegression)
        let passed = !samples.isEmpty && withinBudget && safety

        return Verdict(
            sampleCount: samples.count,
            p50Ms: p50, p95Ms: p95,
            polishedBaselineP95Ms: polishedBaselineP95Ms,
            regression: regression,
            allSafetyStagesPresent: safety,
            passed: passed,
            stagePercentilesMs: stagePercentiles(warmCloud))
    }

    /// Cold-local is reported, never gated with warm-cloud (spec Testing 17: "cold local 单独记录").
    public static func coldLocalReport(_ coldLocal: [IntentLatencyTrace]) -> StagePercentile? {
        let samples = coldLocal.compactMap { $0.stopToVisibleMs }
        guard let p50 = LatencyStats.percentile(samples, 50),
              let p95 = LatencyStats.percentile(samples, 95) else { return nil }
        return StagePercentile(p50Ms: p50, p95Ms: p95)
    }

    private static func stagePercentiles(_ traces: [IntentLatencyTrace]) -> [String: StagePercentile] {
        var out = [String: StagePercentile]()
        for stage in IntentLatencyTrace.Stage.allCases where stage != .stop {
            let durations = traces.compactMap { $0.durationMs(to: stage) }
            if let p50 = LatencyStats.percentile(durations, 50),
               let p95 = LatencyStats.percentile(durations, 95) {
                out[stage.rawValue] = StagePercentile(p50Ms: p50, p95Ms: p95)
            }
        }
        return out
    }
}
