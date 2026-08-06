import Foundation
import OSLog
import ResponsayCore

/// Reads a whole document aloud — a selection, or a long passage pasted into the reader window.
///
/// Different job from `ReadAloudController`, which speaks one short utterance (a Coach line, an
/// Ask answer) by composing all of its audio and then playing it. That shape does not survive a
/// pasted document: composing 3,000 characters up front means a long silent wait, a large audio
/// buffer held in memory, and a speed change that can only be honored by throwing all of it away.
///
/// So this one **pipelines**: slice into lines (`ReadAloudScript`), then synthesize one line at a
/// time and queue it onto the player's gapless streaming input. Playback starts after the first
/// line, memory stays bounded to `prefetchSeconds` of audio ahead of the playhead, and because
/// each line's real duration is recorded (`ReadAloudLineTimeline`) the highlight is exact at line
/// granularity for a document of any length.
@MainActor
@Observable
final class ReadAloudDocumentReader: ReadAloudStoppable {
    enum Phase: Equatable { case idle, preparing, playing, paused }

    private(set) var script = ReadAloudScript(lines: [])
    private(set) var phase: Phase = .idle
    /// Line currently sounding — the one the reader tints. nil before the first line anchors.
    private(set) var activeLine: Int?
    /// 0…1 within `activeLine`, interpolated by elapsed fraction (the character sweep).
    private(set) var lineProgress: Double = 0
    private(set) var errorMessage: String?
    /// Set when the selected engine could not be built and a fallback voice is speaking.
    private(set) var voiceNotice: String?

    /// Speaking rate. Qwen's realtime `rate` accepts 0.5–2.0 (`QwenAudioTTSProtocol`), and the
    /// other providers are clamped to the same window so the control means one thing everywhere.
    static let speedRange: ClosedRange<Double> = 0.5...2.0
    private(set) var speed: Double = 1.0

    var isActive: Bool { phase != .idle }
    var hasText: Bool { !script.isEmpty }

    /// Called when the document finishes on its own (not on `stop()`).
    var onFinished: (@MainActor () -> Void)?

    /// How much synthesized audio to keep queued ahead of the playhead. Two or three lines'
    /// worth: enough that synthesis latency never opens a gap, small enough that a speed or
    /// voice change only has to discard a couple of seconds of work.
    private let prefetchSeconds: TimeInterval = 8
    private let tick: Duration = .milliseconds(60)

    private let player: any ReadAloudAudioPlaying
    private var pipeline: Task<Void, Never>?
    /// Identifies the pipeline allowed to finalize the shared audio stream. A cancelled
    /// synthesizer may still return, so task cancellation alone cannot protect a replacement.
    private var pipelineGeneration: UInt = 0
    private var ticker: Task<Void, Never>?
    /// Line the current audio stream starts at — every restart (speed, voice, jump) rebases here,
    /// so timeline offsets stay relative to the live stream rather than the whole document.
    private var streamOrigin = 0
    private var timeline = ReadAloudLineTimeline()
    private var didReachEnd = false
    /// Rate or voice changed while paused: the queued audio no longer matches the settings, so
    /// resuming has to rebuild it rather than play the stale buffer.
    private var needsRebuildOnResume = false

    var coordinator: ReadAloudCoordinator? = .shared
    /// Injected for tests; production resolves the user's selected TTS engine per read.
    var makeSynthesizer: () -> (synth: any SpeechSynthesizer, fallbackProvider: String?) = {
        let selected = try? TTSEngine.selected.makeSynthesizer()
        if let selected { return (selected, nil) }
        // A missing key must not make a long document unreadable — fall back to whatever can
        // speak (installed Kokoro, else Apple's system voice) and say so in the UI.
        return (TTSEngine.selected.resolvedSynthesizer(), TTSEngine.selected.title)
    }

    private static let log = Logger(
        subsystem: AppBrand.loggerSubsystem, category: "ReadAloudDocument")

    init(player: any ReadAloudAudioPlaying = AudioReadAloudPlayer()) {
        self.player = player
    }

    // MARK: - Text

    /// Replace the document. Any read in flight stops — the old text is gone, so its audio is too.
    func load(_ text: String) {
        stop()
        script = ReadAloudScript(text: text)
        activeLine = nil
        lineProgress = 0
        errorMessage = nil
        voiceNotice = nil
        Self.log.notice("document loaded lines=\(self.script.count, privacy: .public)")
    }

    /// Load `text` and immediately start reading it — the selection hotkey and 划词菜单 path.
    func read(_ text: String) {
        load(text)
        guard hasText else {
            errorMessage = "没有可朗读的文本。"
            return
        }
        start(from: 0)
    }

    // MARK: - Transport

    func start(from line: Int) {
        guard hasText else { return }
        coordinator?.activate(self)
        teardownTasks()
        pipelineGeneration &+= 1
        let generation = pipelineGeneration
        player.stop()
        timeline.reset()
        streamOrigin = max(0, min(line, script.count - 1))
        activeLine = streamOrigin
        lineProgress = 0
        errorMessage = nil
        didReachEnd = false
        needsRebuildOnResume = false
        phase = .preparing
        pipeline = Task { @MainActor [weak self] in
            await self?.runPipeline(generation: generation)
        }
    }

    func pauseOrResume() {
        switch phase {
        case .playing:
            player.pause()
            phase = .paused
        case .paused:
            if needsRebuildOnResume {
                needsRebuildOnResume = false
                start(from: activeLine ?? streamOrigin)
                return
            }
            player.resume()
            phase = .playing
            startTicker()
        case .idle:
            if hasText { start(from: 0) }
        case .preparing:
            break
        }
    }

    func stop() {
        teardownTasks()
        pipelineGeneration &+= 1
        player.stop()
        timeline.reset()
        phase = .idle
        activeLine = nil
        lineProgress = 0
        didReachEnd = false
        needsRebuildOnResume = false
        coordinator?.resign(self)
    }

    /// Restart at `line` — the click-to-read-from-here path.
    func jump(to line: Int) {
        guard script[line] != nil else { return }
        start(from: line)
    }

    /// Apply a new rate. Audio already queued was synthesized at the old rate and cannot be
    /// re-timed, so the read restarts at the head of the line that is sounding — "从本句开始变速",
    /// which is both immediate and honest. Idle just records it for the next read.
    func setSpeed(_ newValue: Double) {
        let clamped = min(Self.speedRange.upperBound, max(Self.speedRange.lowerBound, newValue))
        guard clamped != speed else { return }
        speed = clamped
        restartForSettingChange()
    }

    /// The voice is read fresh from `TTSEngine` on every synthesis call, so switching it only
    /// needs the same restart-at-the-current-line treatment as a rate change.
    func voiceDidChange() {
        restartForSettingChange()
    }

    /// Rate/voice changed: rebuild the queued audio from the current line. While paused, defer
    /// it — a slider drag must not start the audio back up behind the user's back.
    private func restartForSettingChange() {
        switch phase {
        case .playing, .preparing:
            start(from: activeLine ?? streamOrigin)
        case .paused:
            needsRebuildOnResume = true
        case .idle:
            break
        }
    }

    // MARK: - Pipeline

    private func runPipeline(generation: UInt) async {
        let (synth, fallbackProvider) = makeSynthesizer()
        voiceNotice = fallbackProvider.map { "已回退到可用音色朗读（\($0) 未就绪）" }
        var streamStarted = false
        var anchored = false
        var line = streamOrigin
        while line < script.count, !Task.isCancelled {
            // Backpressure: never run more than `prefetchSeconds` ahead of the playhead. This is
            // what keeps a 10,000-character paste from synthesizing (and buffering) all at once.
            while !Task.isCancelled,
                  anchored,
                  timeline.bufferedDuration - player.elapsed > prefetchSeconds {
                try? await Task.sleep(for: tick)
            }
            guard !Task.isCancelled, let entry = script[line] else { break }
            do {
                let speech = try await synth.synthesize(entry.text, speed: speed)
                guard !Task.isCancelled else { break }
                if !streamStarted {
                    do {
                        try player.beginStreaming(sampleRate: Double(speech.sampleRate))
                        streamStarted = true
                    } catch {
                        fail("朗读失败：音频播放没有启动。")
                        return
                    }
                }
                player.appendStreaming(speech)
                timeline.append(line: line, duration: speech.duration)
            } catch {
                guard !Task.isCancelled else { break }
                Self.log.error("line synth failed line=\(line, privacy: .public): \(String(describing: error), privacy: .public)")
                // One bad line should not end the document; skip it and keep reading. Only a
                // first line that produces nothing at all is a visible failure.
                if !anchored, line == streamOrigin, timeline.isEmpty {
                    fail(ReadAloudController.noPlayableSpeechMessage)
                    return
                }
                line += 1
                continue
            }
            if !anchored {
                anchored = await player.waitForPlaybackAnchor(timeout: ReadAloudController.anchorTimeout)
                guard !Task.isCancelled else { break }
                guard anchored else {
                    fail(ReadAloudController.playbackFailedMessage)
                    return
                }
                phase = .playing
                startTicker()
            }
            line += 1
        }
        guard generation == pipelineGeneration else { return }
        player.endStreaming()
        didReachEnd = !Task.isCancelled
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, self.phase == .playing {
                self.sampleClock()
                try? await Task.sleep(for: self.tick)
            }
        }
    }

    private func sampleClock() {
        let elapsed = player.elapsed
        if let line = timeline.activeLine(at: elapsed) {
            activeLine = line
            lineProgress = timeline.progress(at: elapsed)
        }
        // Finished = the pipeline ran out of lines *and* the queued audio has played out.
        guard didReachEnd, elapsed >= timeline.bufferedDuration, timeline.bufferedDuration > 0 else { return }
        let callback = onFinished
        stop()
        callback?()
    }

    private func fail(_ message: String) {
        teardownTasks()
        pipelineGeneration &+= 1
        player.stop()
        phase = .idle
        activeLine = nil
        lineProgress = 0
        errorMessage = message
        coordinator?.resign(self)
    }

    private func teardownTasks() {
        pipeline?.cancel()
        pipeline = nil
        ticker?.cancel()
        ticker = nil
    }
}
