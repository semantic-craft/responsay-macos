import Foundation

/// In-memory PCM buffer for one push-to-talk task. Every reader starts at frame zero, so a stale
/// reused socket can be replaced and the same recording replayed without dropping its prefix.
/// The buffer is task-scoped and released after `stop()`; it is never persisted or logged.
public final class QwenReplayableAudioBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var frames: [Data] = []
    private var readers: [UUID: AsyncStream<Data>.Continuation] = [:]
    private var isFinished = false

    public init() {}

    public func append(_ frame: Data) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        frames.append(frame)
        let continuations = Array(readers.values)
        lock.unlock()
        for continuation in continuations { continuation.yield(frame) }
    }

    public func replayingStream() -> AsyncStream<Data> {
        let id = UUID()
        return AsyncStream { continuation in
            continuation.onTermination = { [weak self] _ in self?.removeReader(id) }
            lock.lock()
            if isFinished {
                let snapshot = frames
                for frame in snapshot { continuation.yield(frame) }
                lock.unlock()
                continuation.finish()
                return
            }
            readers[id] = continuation
            let snapshot = frames
            for frame in snapshot { continuation.yield(frame) }
            lock.unlock()
        }
    }

    public func finish() {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        let continuations = Array(readers.values)
        readers.removeAll()
        lock.unlock()
        for continuation in continuations { continuation.finish() }
    }

    private func removeReader(_ id: UUID) {
        lock.lock()
        readers.removeValue(forKey: id)
        lock.unlock()
    }
}
