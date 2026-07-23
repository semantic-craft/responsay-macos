import Foundation

/// End-to-end dictation latency trace (issue 507). Stamp the boundary of each
/// pipeline stage (record→transcribe→polish→insert), then read per-stage + total
/// ms. Pure value type — no clock, no I/O — so it's headless testable: the caller
/// supplies `Date()` at each boundary, tests supply fixed dates.
///
/// Per-stage durations are computed as the gap to the *previous present mark*, so
/// when a stage is skipped (e.g. 直写 with no polish) the durations still sum to
/// `totalMs` exactly.
public struct LatencyTrace: Sendable, Equatable {
    public enum Stage: String, Sendable, CaseIterable, Codable {
        case record, transcribe, polish, insert
    }

    public private(set) var marks: [Stage: Date]

    public init(marks: [Stage: Date] = [:]) { self.marks = marks }

    public mutating func mark(_ stage: Stage, at time: Date) { marks[stage] = time }

    /// record → transcribe (ASR).
    public var asrMs: Double? { duration(to: .transcribe) }
    /// transcribe → polish.
    public var polishMs: Double? { duration(to: .polish) }
    /// previous present mark → insert.
    public var insertMs: Double? { duration(to: .insert) }
    /// record → insert (user-perceived latency: stopped talking → text appeared).
    public var totalMs: Double? {
        guard let start = marks[.record], let end = marks[.insert] else { return nil }
        return end.timeIntervalSince(start) * 1000
    }

    private static let order: [Stage] = [.record, .transcribe, .polish, .insert]

    /// Gap (ms) from the nearest preceding present mark to `stage`'s mark. nil when
    /// `stage` or every preceding mark is absent. Summing all present stage gaps
    /// reconstructs `totalMs` exactly, even when a middle stage is skipped.
    private func duration(to stage: Stage) -> Double? {
        guard let end = marks[stage],
              let index = Self.order.firstIndex(of: stage), index > 0 else { return nil }
        for previous in Self.order[..<index].reversed() {
            if let start = marks[previous] { return end.timeIntervalSince(start) * 1000 }
        }
        return nil
    }
}

public extension DiagnosticEvent {
    /// Build one end-to-end `pipeline` event from a trace. nil when the trace has
    /// no `totalMs` (record or insert mark missing) — nothing meaningful to report.
    static func pipeline(
        _ trace: LatencyTrace,
        engine: String?,
        provider: String?,
        timestamp: Date
    ) -> DiagnosticEvent? {
        guard let total = trace.totalMs else { return nil }
        func rounded(_ value: Double?) -> String? { value.map { String(Int($0.rounded())) } }
        var fields: [String: String] = ["totalMs": String(Int(total.rounded()))]
        if let value = rounded(trace.asrMs) { fields["asrMs"] = value }
        if let value = rounded(trace.polishMs) { fields["polishMs"] = value }
        if let value = rounded(trace.insertMs) { fields["insertMs"] = value }
        if let engine, !engine.isEmpty { fields["engine"] = engine }
        if let provider, !provider.isEmpty { fields["provider"] = provider }
        return DiagnosticEvent(timestamp: timestamp, category: .pipeline, level: .info,
                               title: "听写延迟", fields: fields)
    }
}
