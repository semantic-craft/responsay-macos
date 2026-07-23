import Foundation

/// One structured event in the speech-stack diagnostics feed (issue 200). Flat
/// `fields` (not a type per event) so any ASR/TTS engine can attach what's relevant
/// — engine / provider / model / voice / durationMs / sampleRate / chunkCount / elapsed.
public struct DiagnosticEvent: Identifiable, Sendable, Equatable {
    public enum Category: String, Sendable, CaseIterable { case asr, tts, llm, pipeline, autolearn }
    public enum Level: String, Sendable { case info, warning, error }

    public let id: UUID
    public let timestamp: Date
    public let category: Category
    public let level: Level
    public let title: String
    public let fields: [String: String]
    /// `TTSError.userMessage` (or any human-facing reason) when `level == .error`.
    public let errorMessage: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        category: Category,
        level: Level,
        title: String,
        fields: [String: String] = [:],
        errorMessage: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.level = level
        self.title = title
        self.fields = fields
        self.errorMessage = errorMessage
    }
}

/// In-app, bounded event bus for the debug diagnostics panel (issue 200). The panel
/// observes `events`; engines `record` to it. Pure logic (no UI, no audio) → headless
/// testable. In release builds the emit sites are `#if DEBUG`-gated, so this carries no
/// production cost; the type itself is always compiled so `ResponsayCore` stays clean.
@MainActor
@Observable
public final class DiagnosticsCenter {
    public static let shared = DiagnosticsCenter()

    /// Newest-last ring buffer; appends past `maxEvents` drop the oldest.
    public private(set) var events: [DiagnosticEvent] = []
    public let maxEvents: Int

    public init(maxEvents: Int = 200) {
        self.maxEvents = max(1, maxEvents)
    }

    public func record(_ event: DiagnosticEvent) {
        events.append(event)
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
    }

    public func clear() { events.removeAll() }

    /// Events for one category, newest first (panel render order).
    public func events(in category: DiagnosticEvent.Category) -> [DiagnosticEvent] {
        events.filter { $0.category == category }.reversed()
    }

    /// Session `totalMs` of every `pipeline` (end-to-end latency) event. The panel
    /// feeds this to `LatencyStats.percentile` for a p50/p95 readout (issue 507).
    public func pipelineTotalsMs() -> [Double] {
        events(in: .pipeline).compactMap { $0.fields["totalMs"].flatMap(Double.init) }
    }
}
