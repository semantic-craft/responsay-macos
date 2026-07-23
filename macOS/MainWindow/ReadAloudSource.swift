import Foundation
import ResponsayCore

/// A read-aloud playback source (issue 198 refactor): bundles the three things the
/// `ReadAloudController` highlight loop needs — the word `timeline`, the current
/// `elapsed` clock, and the `isFinished` end-signal — behind one seam. The controller
/// picks a source (estimated vs real audio) instead of branching on a `usingRealAudio`
/// flag across `step` / `stop` / `pause`, collapsing the Divergent-Change smell.
@MainActor
protocol ReadAloudSource: AnyObject {
    var timeline: [TimedWord] { get }
    var elapsed: TimeInterval { get }
    var isFinished: Bool { get }
    /// Advance an internal clock by `dt` (scaled by `speed`). No-op when an external
    /// clock (the audio player) is authoritative.
    func advance(by dt: TimeInterval, speed: Double)
    /// Restart from the beginning (for 复读 looping).
    func reset()
    func pause()
    func resume()
    func stop()
}

/// Estimated-pace clock over a built timeline — no audio. Pure and headless-testable;
/// used as the immediate fallback and for 复读.
@MainActor
final class EstimatedReadAloudSource: ReadAloudSource {
    let timeline: [TimedWord]
    private(set) var elapsed: TimeInterval = 0
    private var paused = false

    init(timeline: [TimedWord]) { self.timeline = timeline }

    private var total: TimeInterval { ReadAloudTimeline.totalDuration(timeline) }
    var isFinished: Bool { elapsed >= total }

    func advance(by dt: TimeInterval, speed: Double) {
        guard !paused else { return }
        elapsed += dt * max(0.25, speed)
    }

    func reset() { elapsed = 0 }
    func pause() { paused = true }
    func resume() { paused = false }
    func stop() { elapsed = 0; paused = false }
}

/// The slice of `AudioReadAloudPlayer` a playback source needs — a seam (301) so
/// `PlayerReadAloudSource.reset()`'s re-schedule behavior is unit-testable with a
/// mock counting `play` calls. Streaming methods stay on the concrete player.
@MainActor
protocol ReadAloudAudioPlaying: AnyObject {
    var elapsed: TimeInterval { get }
    var isFinished: Bool { get }
    func play(_ composed: ComposedReadAloud) throws
    func waitForPlaybackAnchor(timeout: TimeInterval) async -> Bool
    /// Last-resort playback (484): write the composed PCM to a temp file and play it
    /// with `AVAudioPlayer`, bypassing the (possibly broken) `AVAudioEngine`. Returns
    /// whether playback started; on success drives `elapsed`/`isFinished` from the file
    /// player. Apple system TTS only covers synth-layer failure — this covers the
    /// playback layer, where the engine itself is the problem.
    func playFileEmergency(_ composed: ComposedReadAloud) -> Bool
    func beginStreaming(sampleRate: Double) throws
    @discardableResult
    func appendStreaming(_ speech: SynthesizedSpeech) -> TimeInterval
    func endStreaming()
    func pause()
    func resume()
    func stop()
}

/// Real-audio source: the `AVAudioPlayerNode` clock is authoritative, so `advance` is
/// a no-op and `elapsed`/`isFinished` come from the player. Used for composed
/// whole-utterance audio and for the streaming path (with an estimated-pace timeline,
/// since a live stream carries no per-word timing).
@MainActor
final class PlayerReadAloudSource: ReadAloudSource {
    let timeline: [TimedWord]
    private let player: any ReadAloudAudioPlaying
    /// Retained for 复读 looping (301): `reset()` re-schedules it from 0. nil on
    /// the streaming path — a finished live stream cannot be re-scheduled, so
    /// reset stays a no-op there (the loop then simply ends early).
    private let composed: ComposedReadAloud?
    /// 484: this source is backed by the file-emergency player (the engine path failed),
    /// so a loop restart must replay via emergency — replaying through the still-broken
    /// engine would go silent.
    private let isEmergency: Bool

    init(
        timeline: [TimedWord],
        player: any ReadAloudAudioPlaying,
        composed: ComposedReadAloud? = nil,
        isEmergency: Bool = false
    ) {
        self.timeline = timeline
        self.player = player
        self.composed = composed
        self.isEmergency = isEmergency
    }

    var elapsed: TimeInterval { player.elapsed }
    var isFinished: Bool { player.isFinished }

    func advance(by dt: TimeInterval, speed: Double) {}  // audio clock is authoritative
    /// 301/484: restart the real voice from the top. Replays via the same path that
    /// produced sound the first time — emergency file player when the engine was broken,
    /// otherwise the engine. Failure degrades to ending the loop early, never an infinite
    /// spin (the controller decrements `loopsRemaining` regardless).
    func reset() {
        guard let composed else { return }   // streaming: cannot restart
        if isEmergency {
            _ = player.playFileEmergency(composed)
        } else {
            try? player.play(composed)
        }
    }
    func pause() { player.pause() }
    func resume() { player.resume() }
    func stop() { player.stop() }
}
