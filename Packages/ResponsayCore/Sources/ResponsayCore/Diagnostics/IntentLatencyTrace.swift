import Foundation

/// #567 — the intent-aware dictation latency trace, extending issue 507's `LatencyTrace` shape to
/// the intent pipeline's stages. Pure value type (no clock, no I/O): the caller stamps `Date()` at
/// each stage boundary, tests stamp fixed dates, and #568's real-Mac run supplies warm-cloud
/// samples. Per-stage durations are the gap to the previous PRESENT mark, so a skipped
/// `optionalPolish` (the allowed latency degradation) still lets the present stages sum to
/// `stopToVisibleMs` exactly.
public struct IntentLatencyTrace: Sendable, Equatable {
    /// `stop` = ASR stop boundary (final transcript ready); `visible` = text visible/inserted.
    /// The safety stages (`planVerify`, `sourceRender`, `postRenderGuard`) must never be skipped;
    /// `optionalPolish` may be dropped under latency pressure (spec Testing 17 / AC8).
    public enum Stage: String, Sendable, CaseIterable, Codable {
        case stop, compile, planVerify, sourceRender, optionalPolish, postRenderGuard, visible
    }

    /// The safety stages that a compliant pipeline may never skip, even when shedding latency.
    public static let safetyStages: [Stage] = [.planVerify, .sourceRender, .postRenderGuard]

    public private(set) var marks: [Stage: Date]

    public init(marks: [Stage: Date] = [:]) { self.marks = marks }

    public mutating func mark(_ stage: Stage, at time: Date) { marks[stage] = time }

    private static let order: [Stage] = [
        .stop, .compile, .planVerify, .sourceRender, .optionalPolish, .postRenderGuard, .visible
    ]

    /// User-perceived latency: stopped talking → text appeared. nil when either boundary is absent.
    public var stopToVisibleMs: Double? {
        guard let start = marks[.stop], let end = marks[.visible] else { return nil }
        return end.timeIntervalSince(start) * 1000
    }

    /// Gap (ms) from the nearest preceding present mark to `stage`'s mark. Summing every present
    /// stage gap reconstructs `stopToVisibleMs` exactly, even when a middle stage is skipped.
    public func durationMs(to stage: Stage) -> Double? {
        guard let end = marks[stage],
              let index = Self.order.firstIndex(of: stage), index > 0 else { return nil }
        for previous in Self.order[..<index].reversed() {
            if let start = marks[previous] { return end.timeIntervalSince(start) * 1000 }
        }
        return nil
    }

    /// Whether every non-skippable safety stage was stamped — the AC8 invariant: latency shedding
    /// may drop `optionalPolish`, never a safety stage.
    public var safetyStagesPresent: Bool {
        Self.safetyStages.allSatisfy { marks[$0] != nil }
    }
}

public extension DiagnosticEvent {
    /// #568 — one `pipeline` event from a completed Intent-aware warm trace, for the on-device
    /// latency run (the real-Mac reads these off the diagnostics panel / OSLog into the report).
    /// Numeric per-stage ms + route/provider labels ONLY — never raw text, draft or plan (privacy).
    /// nil when there is no `stopToVisibleMs` (an incomplete trace is not a warm sample).
    static func intentPipeline(
        _ trace: IntentLatencyTrace,
        route: String?,
        provider: String?,
        timestamp: Date
    ) -> DiagnosticEvent? {
        guard let total = trace.stopToVisibleMs else { return nil }
        func rounded(_ value: Double?) -> String? { value.map { String(Int($0.rounded())) } }
        var fields: [String: String] = [
            "totalMs": String(Int(total.rounded())),
            "safetyStagesPresent": trace.safetyStagesPresent ? "1" : "0"
        ]
        if let value = rounded(trace.durationMs(to: .compile)) { fields["compileMs"] = value }
        if let value = rounded(trace.durationMs(to: .planVerify)) { fields["planVerifyMs"] = value }
        if let value = rounded(trace.durationMs(to: .sourceRender)) { fields["sourceRenderMs"] = value }
        if let value = rounded(trace.durationMs(to: .optionalPolish)) { fields["optionalPolishMs"] = value }
        if let value = rounded(trace.durationMs(to: .postRenderGuard)) { fields["postRenderGuardMs"] = value }
        if let value = rounded(trace.durationMs(to: .visible)) { fields["visibleMs"] = value }
        if let route, !route.isEmpty { fields["route"] = route }
        if let provider, !provider.isEmpty { fields["provider"] = provider }
        return DiagnosticEvent(timestamp: timestamp, category: .pipeline, level: .info,
                               title: "校验成稿延迟", fields: fields)
    }
}
