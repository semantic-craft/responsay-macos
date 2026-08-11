import Foundation

extension QwenRunTaskSession {
    /// Buffers one caller-owned PCM stream so a replacement transport can replay every frame from
    /// the beginning without making replay part of the session interface.
    final class ReplayableAudio: @unchecked Sendable {
        private let lock = NSLock()
        private var frames: [Data] = []
        private var readers: [UUID: AsyncStream<Data>.Continuation] = [:]
        private var isFinished = false
        private var pump: Task<Void, Never>?

        init(source: AsyncStream<Data>) {
            pump = Task { [weak self] in
                for await frame in source {
                    guard !Task.isCancelled else { break }
                    self?.append(frame)
                }
                self?.finish()
            }
        }

        func replayingStream() -> AsyncStream<Data> {
            let id = UUID()
            return AsyncStream { continuation in
                continuation.onTermination = { [weak self] _ in self?.removeReader(id) }
                lock.lock()
                if isFinished {
                    for frame in frames { continuation.yield(frame) }
                    lock.unlock()
                    continuation.finish()
                    return
                }
                readers[id] = continuation
                for frame in frames { continuation.yield(frame) }
                lock.unlock()
            }
        }

        func cancel() {
            pump?.cancel()
            finish()
        }

        private func append(_ frame: Data) {
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

        private func finish() {
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
}
