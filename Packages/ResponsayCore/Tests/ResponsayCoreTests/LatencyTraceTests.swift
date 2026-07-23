import Testing
import Foundation
@testable import ResponsayCore

/// 507 — end-to-end dictation latency: stage trace + p50/p95 math + pipeline event.
/// T1 headless (pure logic, fixed dates — no clock, no audio, no network).
struct LatencyTraceTests {
    private let base = Date(timeIntervalSince1970: 1000)

    /// Trace from second-offsets; nil offset = mark omitted.
    private func trace(record: Double?, transcribe: Double?, polish: Double?, insert: Double?) -> LatencyTrace {
        var t = LatencyTrace()
        func add(_ s: LatencyTrace.Stage, _ off: Double?) { if let off { t.mark(s, at: base.addingTimeInterval(off)) } }
        add(.record, record); add(.transcribe, transcribe); add(.polish, polish); add(.insert, insert)
        return t
    }

    private func ms(_ v: Double?) -> Int? { v.map { Int($0.rounded()) } }

    @Test func computesPerStageAndTotalMs() {
        // record@0 · transcribe@0.4 (asr 400) · polish@0.5 (polish 100) · insert@0.55 (insert 50)
        let t = trace(record: 0, transcribe: 0.4, polish: 0.5, insert: 0.55)
        #expect(ms(t.asrMs) == 400)
        #expect(ms(t.polishMs) == 100)
        #expect(ms(t.insertMs) == 50)
        #expect(ms(t.totalMs) == 550)
    }

    @Test func stageDurationsSumToTotal() {
        let t = trace(record: 0, transcribe: 0.4, polish: 0.5, insert: 0.55)
        let sum = (t.asrMs ?? 0) + (t.polishMs ?? 0) + (t.insertMs ?? 0)
        #expect(abs(sum - (t.totalMs ?? -1)) < 0.001)
    }

    @Test func skippedPolishStillSumsToTotal() {
        // no polish mark → insert duration spans transcribe→insert; sum still == total
        let t = trace(record: 0, transcribe: 0.4, polish: nil, insert: 0.5)
        #expect(t.polishMs == nil)
        #expect(ms(t.asrMs) == 400)
        #expect(ms(t.insertMs) == 100)            // 0.5 - 0.4
        let sum = (t.asrMs ?? 0) + (t.insertMs ?? 0)
        #expect(abs(sum - (t.totalMs ?? -1)) < 0.001)  // total = 500
    }

    @Test func missingBoundsYieldNil() {
        let t = trace(record: nil, transcribe: 0.4, polish: nil, insert: nil)
        #expect(t.totalMs == nil)                 // no insert (and no record)
        #expect(t.asrMs == nil)                   // no record bound
    }

    @Test func pipelineEventCarriesStageFields() {
        let t = trace(record: 0, transcribe: 0.4, polish: 0.5, insert: 0.55)
        let ev = DiagnosticEvent.pipeline(t, engine: "Qwen3-local", provider: "qwen",
                                          timestamp: Date(timeIntervalSince1970: 2000))
        #expect(ev?.category == .pipeline)
        #expect(ev?.level == .info)
        #expect(ev?.fields["totalMs"] == "550")
        #expect(ev?.fields["asrMs"] == "400")
        #expect(ev?.fields["polishMs"] == "100")
        #expect(ev?.fields["insertMs"] == "50")
        #expect(ev?.fields["engine"] == "Qwen3-local")
        #expect(ev?.fields["provider"] == "qwen")
    }

    @Test func pipelineEventNilWithoutTotal() {
        let t = trace(record: nil, transcribe: nil, polish: nil, insert: 0.5)
        #expect(DiagnosticEvent.pipeline(t, engine: nil, provider: nil, timestamp: base) == nil)
    }

    @Test func pipelineEventOmitsEmptyEngineProvider() {
        let t = trace(record: 0, transcribe: nil, polish: nil, insert: 0.3)
        let ev = DiagnosticEvent.pipeline(t, engine: "", provider: nil, timestamp: base)
        #expect(ev?.fields["engine"] == nil)
        #expect(ev?.fields["provider"] == nil)
        #expect(ev?.fields["totalMs"] == "300")
    }
}

struct LatencyStatsTests {
    @Test func emptyIsNil() { #expect(LatencyStats.percentile([], 50) == nil) }

    @Test func singleValue() { #expect(LatencyStats.percentile([42], 95) == 42) }

    @Test func nearestRankP50P95P90() {
        let v = [10.0, 20, 30, 40, 50, 60, 70, 80, 90, 100]  // n=10
        #expect(LatencyStats.percentile(v, 50) == 50)   // ceil(0.5*10)=5 → idx4
        #expect(LatencyStats.percentile(v, 90) == 90)   // ceil(0.9*10)=9 → idx8
        #expect(LatencyStats.percentile(v, 95) == 100)  // ceil(0.95*10)=10 → idx9
    }

    @Test func sortsUnsortedInput() {
        #expect(LatencyStats.percentile([30, 10, 20], 50) == 20)  // [10,20,30], ceil(1.5)=2 → idx1
    }

    @Test func clampsOutOfRangeP() {
        #expect(LatencyStats.percentile([10, 20, 30], 0) == 10)
        #expect(LatencyStats.percentile([10, 20, 30], 100) == 30)
    }
}

@MainActor
struct DiagnosticsCenterPipelineTests {
    @Test func pipelineTotalsMsExtractsTotals() {
        let center = DiagnosticsCenter()
        let b = Date(timeIntervalSince1970: 0)
        var t1 = LatencyTrace(); t1.mark(.record, at: b); t1.mark(.insert, at: b.addingTimeInterval(0.3))
        var t2 = LatencyTrace(); t2.mark(.record, at: b); t2.mark(.insert, at: b.addingTimeInterval(0.5))
        center.record(.pipeline(t1, engine: nil, provider: nil, timestamp: b)!)
        center.record(.pipeline(t2, engine: nil, provider: nil, timestamp: b)!)
        center.record(.init(timestamp: b, category: .asr, level: .info, title: "noise"))
        #expect(center.pipelineTotalsMs().sorted() == [300, 500])  // asr event ignored
    }
}
