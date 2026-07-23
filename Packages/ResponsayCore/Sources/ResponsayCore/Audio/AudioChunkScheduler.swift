import Foundation

// MARK: - 134 AVAudioEngine prefetch scheduling (device-independent core)
//
// Pure planner for gapless chunk playback: given each synthesized chunk's
// duration, compute a seamless timeline (cumulative offsets, no gap/overlap)
// and the look-ahead set to prefetch. The actual `AVAudioPlayerNode`
// scheduling consumes this plan (real-Mac gated).

public struct ScheduledSegment: Sendable, Equatable {
    public let index: Int
    public let startOffset: TimeInterval
    public let duration: TimeInterval
    public var endOffset: TimeInterval { startOffset + duration }

    public init(index: Int, startOffset: TimeInterval, duration: TimeInterval) {
        self.index = index
        self.startOffset = startOffset
        self.duration = duration
    }
}

public struct AudioChunkScheduler: Sendable {
    /// Default look-ahead window: prefetch this many upcoming chunks.
    public static let defaultLookAhead = 2

    public let lookAhead: Int

    public init(lookAhead: Int = AudioChunkScheduler.defaultLookAhead) {
        self.lookAhead = max(1, lookAhead)
    }

    /// Lay chunks end-to-end with cumulative offsets (seamless — each segment
    /// starts exactly where the previous ended).
    public func schedule(durations: [TimeInterval]) -> [ScheduledSegment] {
        var segments: [ScheduledSegment] = []
        var cursor: TimeInterval = 0
        for (index, duration) in durations.enumerated() {
            let safe = max(0, duration)
            segments.append(ScheduledSegment(index: index, startOffset: cursor, duration: safe))
            cursor += safe
        }
        return segments
    }

    public func totalDuration(durations: [TimeInterval]) -> TimeInterval {
        durations.reduce(0) { $0 + max(0, $1) }
    }

    /// Indices to have buffered while `playingIndex` plays: the current chunk
    /// plus the next `lookAhead`, clamped to the chunk count.
    public func prefetchWindow(playingIndex: Int, count: Int) -> [Int] {
        guard count > 0 else { return [] }
        let lower = max(0, playingIndex)
        let upper = min(count - 1, playingIndex + lookAhead)
        guard lower <= upper else { return [] }
        return Array(lower...upper)
    }
}
