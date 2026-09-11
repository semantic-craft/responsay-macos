import Foundation
import ResponsayCore

/// Complete-utterance lifecycle. All operations are serialized on the main actor;
/// the generation captured at notification delivery prevents queued work reviving a
/// stopped utterance or resetting a newer one. The injected transport never needs a device in tests.
@MainActor
final class ReadAloudConfigChange {
    enum Intent { case stopped, playing, paused }
    private(set) var intent = Intent.stopped
    private(set) var generation = UUID()
    private(set) var composed: ComposedReadAloud?
    private(set) var position: TimeInterval = 0
    private var offset: TimeInterval = 0
    private var recoveryDeadline: Date?
    var onFailure: ((Error) -> Void)?
    let clock: () -> TimeInterval?
    let schedule: (ComposedReadAloud, TimeInterval, Bool) throws -> Void
    let halt: () -> Void

    init(clock: @escaping () -> TimeInterval?,
         schedule: @escaping (ComposedReadAloud, TimeInterval, Bool) throws -> Void,
         halt: @escaping () -> Void) {
        self.clock = clock
        self.schedule = schedule
        self.halt = halt
    }

    var elapsed: TimeInterval {
        if intent == .playing, let time = clock(), time.isFinite, time >= 0,
           let composed {
            if time > 0 { recoveryDeadline = nil }
            position = min(composed.totalDuration, max(position, offset + time))
        }
        return position
    }

    func start(_ audio: ComposedReadAloud) throws {
        stop()
        composed = audio
        do {
            try schedule(audio, 0, true)
            intent = .playing
        } catch {
            stop()
            throw error
        }
    }

    func pause() {
        guard intent == .playing else { return }
        _ = elapsed
        intent = .paused
    }

    func resume() {
        if intent == .paused {
            intent = .playing
            recoveryDeadline = Date().addingTimeInterval(0.35)
        }
    }

    func checkRecoveryClock(now: Date = Date()) {
        _ = elapsed
        guard intent == .playing, let deadline = recoveryDeadline, now >= deadline else { return }
        stop()
        onFailure?(TTSError.synthesisFailed("音频设备切换后播放时钟未恢复"))
    }

    func stop() {
        generation = UUID()
        intent = .stopped
        composed = nil
        position = 0
        offset = 0
        recoveryDeadline = nil
        halt()
    }

    func recover(generation expected: UUID) {
        guard expected == generation, intent != .stopped, let composed else { return }
        // The render clock may already have disappeared. Keep the last observed
        // position rather than treating a missing clock as the start of the text.
        offset = elapsed
        halt()
        recoveryDeadline = nil
        guard offset < composed.totalDuration else { return }
        do {
            try schedule(composed, offset, intent == .playing)
            recoveryDeadline = intent == .playing ? Date().addingTimeInterval(0.35) : nil
        } catch {
            stop()
            onFailure?(error)
        }
    }

    /// Trim in source-frame coordinates before converting for the new output rate.
    /// Each chunk's own rate determines its duration; silence remains part of time.
    static func remainingChunks(_ chunks: [SynthesizedSpeech], after seconds: TimeInterval) -> [SynthesizedSpeech] {
        var remaining = max(0, seconds)
        return chunks.compactMap { chunk in
            guard chunk.sampleRate > 0 else { return nil }
            let duration = Double(chunk.samples.count) / Double(chunk.sampleRate)
            if remaining >= duration { remaining -= duration; return nil }
            let skip = min(chunk.samples.count, Int((remaining * Double(chunk.sampleRate)).rounded(.down)))
            remaining = 0
            return SynthesizedSpeech(samples: Array(chunk.samples.dropFirst(skip)), sampleRate: chunk.sampleRate)
        }
    }
}
