import Foundation

/// Where each spoken line sits on the audio clock, grown one line at a time as the pipeline
/// synthesizes ahead of playback.
///
/// Line boundaries are **measured**, not estimated: each entry's duration is the real length of
/// that line's audio, so `activeLine(at:)` can never drift onto the wrong sentence no matter how
/// long the document runs. `progress(at:)` interpolates *within* a line by elapsed fraction —
/// that part is an estimate, which is why the reader also tints the whole active line: the tint
/// is always right even when the character-level sweep runs slightly ahead or behind.
public struct ReadAloudLineTimeline: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        public let line: Int
        public let start: TimeInterval
        public let duration: TimeInterval

        public var end: TimeInterval { start + duration }

        public init(line: Int, start: TimeInterval, duration: TimeInterval) {
            self.line = line
            self.start = start
            self.duration = duration
        }
    }

    public private(set) var entries: [Entry] = []

    public init() {}

    public init(entries: [Entry]) {
        self.entries = entries
    }

    /// Total audio queued so far. Also the start offset for the next line.
    public var bufferedDuration: TimeInterval { entries.last?.end ?? 0 }
    public var isEmpty: Bool { entries.isEmpty }
    /// The last line appended, or nil before the first.
    public var lastLine: Int? { entries.last?.line }

    /// Append one synthesized line, laid end-to-end after everything already queued.
    /// Non-positive durations are dropped — a zero-length entry would make `activeLine`
    /// unreachable for that line and stall the highlight on its predecessor.
    public mutating func append(line: Int, duration: TimeInterval) {
        guard duration.isFinite, duration > 0 else { return }
        entries.append(Entry(line: line, start: bufferedDuration, duration: duration))
    }

    public mutating func reset() { entries = [] }

    /// The line sounding at `elapsed`. Clamps to the last queued line past the end, so the
    /// highlight rests on the final sentence instead of blanking while the tail plays out.
    public func activeLine(at elapsed: TimeInterval) -> Int? {
        guard !entries.isEmpty else { return nil }
        if elapsed < entries[0].start { return entries[0].line }
        for entry in entries where elapsed >= entry.start && elapsed < entry.end {
            return entry.line
        }
        return entries.last?.line
    }

    /// How far into the active line we are, 0…1. Used for the character sweep only.
    public func progress(at elapsed: TimeInterval) -> Double {
        guard let entry = entries.first(where: { elapsed >= $0.start && elapsed < $0.end })
        else { return entries.isEmpty || elapsed < (entries.first?.start ?? 0) ? 0 : 1 }
        return min(1, max(0, (elapsed - entry.start) / entry.duration))
    }

    /// Audio clock offset where `line` begins, if it has been queued.
    public func start(ofLine line: Int) -> TimeInterval? {
        entries.first { $0.line == line }?.start
    }
}
