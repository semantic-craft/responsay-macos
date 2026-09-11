import Foundation

/// Tracks the lifetime of a stream, including the queued tail after synthesis ends.
/// Callers serialize audio delivery with their request generation on the main actor.
struct ReadAloudStreamState {
    private(set) var generation: UUID?
    private(set) var acceptsAudio = false
    private(set) var duration: TimeInterval = 0
    private(set) var position: TimeInterval = 0

    var isFinished: Bool { !acceptsAudio && duration > 0 && position >= duration }

    mutating func begin(generation: UUID) {
        self = Self()
        self.generation = generation
        acceptsAudio = true
    }

    mutating func append(duration: TimeInterval) {
        guard acceptsAudio else { return }
        self.duration += duration
    }

    mutating func observe(_ elapsed: TimeInterval?) {
        guard let elapsed, elapsed.isFinite else { return }
        position = min(duration, max(position, elapsed))
    }

    mutating func end() { acceptsAudio = false }
    mutating func stop() { self = Self() }

    /// Consumes a failure at most once. Finished audio and obsolete events are inert.
    mutating func configurationChanged(generation expected: UUID) -> Bool {
        guard generation == expected, !isFinished else { return false }
        stop()
        return true
    }
}

enum ReadAloudPlaybackFailure: LocalizedError {
    case outputChanged
    var errorDescription: String? { "朗读失败：音频输出已变化，请重试。" }
}
