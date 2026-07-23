import AVFoundation
import OSLog
import ResponsayCore

/// Plays a `ComposedReadAloud`'s chunks gaplessly on an `AVAudioPlayerNode` and
/// exposes the real playback `elapsed` time so `ReadAloudController` can drive the
/// word highlight from the audio clock instead of an estimate (issue 194).
///
/// Real audio output is **not** verifiable in the simulator / headless (CLAUDE.md);
/// the scheduling math + elapsed clock are correct by construction and exercised on
/// a real Mac (test standard T3). The estimated-clock path remains the fallback.
@MainActor
final class AudioReadAloudPlayer: ReadAloudAudioPlaying {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var startSampleTime: AVAudioFramePosition?
    private var sampleRate: Double = 24_000
    private var totalDuration: TimeInterval = 0
    /// 483: the composed utterance currently on the engine path, retained so a device /
    /// sample-rate change can re-schedule it. nil for streaming / emergency / idle.
    private var currentComposed: ComposedReadAloud?
    /// 483: whether engine-path audio is live. We can't read `node.isPlaying` in the
    /// config-change handler — the engine has usually already stopped by then.
    private var isActive = false
    // Written once in init, read once in nonisolated deinit — safe to opt out of isolation.
    private nonisolated(unsafe) var configChangeObserver: NSObjectProtocol?
    private var isReplayingForConfigChange = false
    private static let log = Logger(
        subsystem: "com.semanticcraft.responsay.mac", category: "ReadAloudAudio")

    init() {
        engine.attach(node)
        // 483: react to output-device / sample-rate changes (AirPods ↔ built-in ↔ HDMI).
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleConfigurationChange() }
        }
    }

    deinit {
        if let configChangeObserver { NotificationCenter.default.removeObserver(configChangeObserver) }
    }

    /// Elapsed playback time in seconds (0 before start, clamped to total).
    var elapsed: TimeInterval {
        if let emergencyPlayer { return min(emergencyPlayer.currentTime, totalDuration) }  // 484
        guard let playerTime = anchorIfAvailable() else { return 0 }
        guard let startSampleTime else { return 0 }
        let frames = playerTime.sampleTime - startSampleTime
        let seconds = Double(max(0, frames)) / sampleRate
        return min(seconds, totalDuration)
    }

    var isFinished: Bool {
        // 484: the file emergency player reports finish via `isPlaying` going false.
        if let emergencyPlayer { return !emergencyPlayer.isPlaying }
        return elapsed >= totalDuration && totalDuration > 0
    }

    /// Schedule the composed chunks and start playing. Throws if audio setup fails.
    func play(_ composed: ComposedReadAloud) throws {
        stop()
        guard let first = composed.chunks.first else {
            Self.log.error("play failed: composed audio has no chunks")
            throw TTSError.providerReturnedNoAudio(provider: "ReadAloud")
        }
        sampleRate = Double(first.sampleRate)
        totalDuration = composed.totalDuration
        guard sampleRate.isFinite, sampleRate > 0, totalDuration.isFinite, totalDuration > 0 else {
            Self.log.error("play failed: invalid duration or sample rate")
            throw TTSError.providerReturnedNoAudio(provider: "ReadAloud")
        }
        let sampleCount = composed.chunks.reduce(0) { $0 + $1.samples.count }
        Self.log.notice(
            "play start chunks=\(composed.chunks.count, privacy: .public) samples=\(sampleCount, privacy: .public) durationMs=\(Int(composed.totalDuration * 1000), privacy: .public) rate=\(Int(self.sampleRate), privacy: .public)"
        )
        guard let sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
            channels: 1, interleaved: false) else {
            Self.log.error("play failed: could not create pcm format rate=\(Int(self.sampleRate), privacy: .public)")
            throw TTSError.synthesisFailed("无法创建音频格式")
        }
        // 482: convert to the engine's output sample rate when they differ (24k ↔ 48k);
        // on any converter failure, fall back to scheduling the source buffers directly
        // (the engine resamples downstream — the proven path).
        let outputRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let prepared = makeScheduledBuffers(for: composed, sourceFormat: sourceFormat, outputRate: outputRate)
        guard !prepared.buffers.isEmpty else {
            Self.log.error("play failed: no non-empty audio buffers scheduled")
            throw TTSError.providerReturnedNoAudio(provider: "ReadAloud")
        }
        // The node renders in the play format, so the elapsed clock counts frames at that rate.
        sampleRate = prepared.format.sampleRate
        Self.log.notice(
            "play format sourceRate=\(Int(sourceFormat.sampleRate), privacy: .public) playRate=\(Int(prepared.format.sampleRate), privacy: .public) converted=\(prepared.converted, privacy: .public) convertedFrames=\(prepared.totalFrames, privacy: .public) converterError=\(prepared.converterFailed, privacy: .public)"
        )
        engine.connect(node, to: engine.mainMixerNode, format: prepared.format)
        node.volume = 1
        engine.mainMixerNode.outputVolume = 1
        engine.prepare()
        try engine.start()
        let scheduled = prepared.buffers.count
        for buffer in prepared.buffers {
            node.scheduleBuffer(buffer, completionHandler: nil)
        }
        currentComposed = composed   // 483: retained so a config change can re-schedule
        isActive = true
        node.play()
        if let nodeTime = node.lastRenderTime,
           let playerTime = node.playerTime(forNodeTime: nodeTime),
           playerTime.sampleTime >= 0 {
            startSampleTime = playerTime.sampleTime
            Self.log.notice(
                "play node started scheduled=\(scheduled, privacy: .public) anchor=\(playerTime.sampleTime, privacy: .public)"
            )
        } else {
            startSampleTime = nil
            Self.log.notice("play node started scheduled=\(scheduled, privacy: .public) anchor=pending")
        }
    }

    func waitForPlaybackAnchor(timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if anchorIfAvailable() != nil { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        Self.log.error("play failed: playback anchor timed out")
        return false
    }

    func pause() {
        if let emergencyPlayer { emergencyPlayer.pause(); return }  // 484
        node.pause()
    }
    func resume() {
        if let emergencyPlayer { emergencyPlayer.play(); return }  // 484
        node.play()
    }

    func stop() {
        node.stop()
        if engine.isRunning { engine.stop() }
        emergencyPlayer?.stop()   // 484
        emergencyPlayer = nil
        currentComposed = nil      // 483
        isActive = false
        startSampleTime = nil
        totalDuration = 0
        streaming = false
        streamFormat = nil
        accumulated = 0
    }

    // MARK: - 484 file-level emergency playback

    /// Retained for the lifetime of emergency playback; nil otherwise.
    private var emergencyPlayer: AVAudioPlayer?

    /// Last resort when the `AVAudioEngine` path keeps failing: render the composed PCM
    /// to a temp CAF and play it with `AVAudioPlayer` (no engine). Returns whether
    /// playback started.
    ///
    /// ponytail: writes the file synchronously on the main actor — fine for a short
    /// coach sentence; revisit if very long utterances ever hit this rare path.
    func playFileEmergency(_ composed: ComposedReadAloud) -> Bool {
        stop()
        guard let first = composed.chunks.first else { return false }
        let rate = Double(first.sampleRate)
        let samples = composed.chunks.flatMap(\.samples)
        guard rate.isFinite, rate > 0,
              !samples.isEmpty, samples.contains(where: { $0 != 0 }),
              let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false),
              let buffer = Self.buffer(from: samples, format: format) else {
            Self.log.error("emergency play failed: invalid composed audio")
            return false
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("readaloud-\(UUID().uuidString).caf")
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
            let data = try Data(contentsOf: url)          // load into memory so the temp file can go
            try? FileManager.default.removeItem(at: url)
            let player = try AVAudioPlayer(data: data)
            player.volume = 1
            guard player.prepareToPlay(), player.play() else {
                Self.log.error("emergency play failed: prepare/play returned false")
                return false
            }
            emergencyPlayer = player
            sampleRate = rate
            totalDuration = player.duration
            Self.log.notice(
                "emergency play started tempFileBytes=\(data.count, privacy: .public) durationMs=\(Int(player.duration * 1000), privacy: .public)"
            )
            return true
        } catch {
            try? FileManager.default.removeItem(at: url)
            Self.log.error("emergency play failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    // MARK: - 197 incremental streaming playback

    private var streaming = false
    private var accumulated: TimeInterval = 0
    private var streamFormat: AVAudioFormat?

    /// Begin a streaming session (issue 197): start the node and accept chunks as
    /// they arrive, for low time-to-first-audio. `elapsed` / `totalDuration` grow as
    /// chunks are appended (we don't know the full length up front).
    func beginStreaming(sampleRate: Double) throws {
        stop()
        self.sampleRate = sampleRate
        guard sampleRate.isFinite, sampleRate > 0 else {
            Self.log.error("streaming play failed: invalid sample rate")
            throw TTSError.providerReturnedNoAudio(provider: "ReadAloud")
        }
        Self.log.notice("streaming play start rate=\(Int(sampleRate), privacy: .public)")
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
            channels: 1, interleaved: false) else {
            Self.log.error("streaming play failed: could not create pcm format")
            throw TTSError.synthesisFailed("无法创建音频格式")
        }
        streamFormat = format
        engine.connect(node, to: engine.mainMixerNode, format: format)
        node.volume = 1
        engine.mainMixerNode.outputVolume = 1
        engine.prepare()
        try engine.start()
        node.play()
        if let nodeTime = node.lastRenderTime,
           let playerTime = node.playerTime(forNodeTime: nodeTime) {
            startSampleTime = playerTime.sampleTime
            Self.log.notice("streaming node started anchor=\(playerTime.sampleTime, privacy: .public)")
        } else {
            startSampleTime = nil
            Self.log.notice("streaming node started anchor=pending")
        }
        streaming = true
    }

    /// Schedule one streaming chunk on the player node; returns the new accumulated
    /// total duration. Buffers queue gaplessly behind whatever is already playing.
    @discardableResult
    func appendStreaming(_ speech: SynthesizedSpeech) -> TimeInterval {
        guard streaming, let format = streamFormat,
              let buffer = Self.buffer(from: speech.samples, format: format) else {
            Self.log.error("streaming append skipped: no active stream or empty buffer")
            return accumulated
        }
        node.scheduleBuffer(buffer, completionHandler: nil)
        accumulated += speech.duration
        totalDuration = accumulated
        Self.log.notice(
            "streaming chunk scheduled samples=\(speech.samples.count, privacy: .public) totalMs=\(Int(self.totalDuration * 1000), privacy: .public)"
        )
        return accumulated
    }

    /// No more chunks will arrive — the accumulated duration is now final.
    func endStreaming() { streaming = false }

    // MARK: - 483 output-device / sample-rate change recovery

    /// The engine stops when the output device or sample rate changes (AirPods ↔
    /// built-in ↔ HDMI). Re-schedule the current utterance with a format rebuilt for the
    /// new hardware. Streaming and emergency playback can't be re-scheduled, so they fall
    /// through silently. Runs async off the notification — never tears the engine down in
    /// the notification handler.
    ///
    /// ponytail: a sync re-entry flag, not a debounce window. A real hardware change is a
    /// physical, infrequent event and our own reconnect doesn't re-post it; add a
    /// time-window debounce only if a device is ever seen to flap.
    private func handleConfigurationChange() {
        guard !isReplayingForConfigChange else { return }
        let outputRateBefore = engine.outputNode.outputFormat(forBus: 0).sampleRate
        guard ReadAloudConfigChange.shouldReplay(wasActive: isActive, hasUtterance: currentComposed != nil),
              let composed = currentComposed else {
            Self.log.notice(
                "audioConfigurationChanged wasPlaying=\(self.isActive, privacy: .public) replayScheduled=false outputRateBefore=\(Int(outputRateBefore), privacy: .public)"
            )
            return
        }
        isReplayingForConfigChange = true
        defer { isReplayingForConfigChange = false }
        do {
            try play(composed)   // stop()+reconnect rebuilds the format for the new hardware
            let outputRateAfter = engine.outputNode.outputFormat(forBus: 0).sampleRate
            Self.log.notice(
                "audioConfigurationChanged wasPlaying=true replayScheduled=true outputRateBefore=\(Int(outputRateBefore), privacy: .public) outputRateAfter=\(Int(outputRateAfter), privacy: .public)"
            )
        } catch {
            Self.log.error("audioConfigurationChanged replay failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - 482 sample-rate / format conversion

    private struct ScheduledBuffers {
        let format: AVAudioFormat
        let buffers: [AVAudioPCMBuffer]
        let converted: Bool
        let converterFailed: Bool
        var totalFrames: Int { buffers.reduce(0) { $0 + Int($1.frameLength) } }
    }

    /// Convert the composed chunks to `outputRate` when it differs from the source rate,
    /// else return the source buffers (the engine resamples downstream). Any converter
    /// failure falls back to the source buffers so playback never breaks on conversion.
    private func makeScheduledBuffers(
        for composed: ComposedReadAloud,
        sourceFormat: AVAudioFormat,
        outputRate: Double
    ) -> ScheduledBuffers {
        let sourceBuffers = composed.chunks.compactMap { Self.buffer(from: $0.samples, format: sourceFormat) }
        let sourceRate = sourceFormat.sampleRate
        guard outputRate.isFinite, outputRate > 0, abs(outputRate - sourceRate) > 1,
              let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: outputRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            return ScheduledBuffers(
                format: sourceFormat, buffers: sourceBuffers, converted: false, converterFailed: false)
        }
        var converted: [AVAudioPCMBuffer] = []
        for src in sourceBuffers {
            guard let out = Self.convert(src, using: converter, to: targetFormat) else {
                return ScheduledBuffers(
                    format: sourceFormat, buffers: sourceBuffers, converted: false, converterFailed: true)
            }
            converted.append(out)
        }
        return ScheduledBuffers(
            format: targetFormat, buffers: converted, converted: true, converterFailed: false)
    }

    private static func convert(
        _ src: AVAudioPCMBuffer, using converter: AVAudioConverter, to target: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let capacity = AVAudioFrameCount(ReadAloudResampling.outputFrameCount(
            sourceFrames: Int(src.frameLength),
            sourceRate: src.format.sampleRate,
            targetRate: target.sampleRate)) + 1024
        guard capacity > 0, let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var fed = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, inputStatus in
            if fed { inputStatus.pointee = .noDataNow; return nil }
            fed = true
            inputStatus.pointee = .haveData
            return src
        }
        guard status != .error, error == nil, out.frameLength > 0 else { return nil }
        return out
    }

    private static func buffer(from samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              samples.allSatisfy(\.isFinite),
              samples.contains(where: { $0 != 0 }),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData else { return nil }
        samples.withUnsafeBufferPointer { src in
            channel[0].update(from: src.baseAddress!, count: samples.count)
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        guard buffer.frameLength > 0 else { return nil }
        return buffer
    }

    private func anchorIfAvailable() -> AVAudioTime? {
        guard let nodeTime = node.lastRenderTime,
              let playerTime = node.playerTime(forNodeTime: nodeTime),
              playerTime.sampleTime >= 0 else { return nil }
        if startSampleTime == nil {
            startSampleTime = playerTime.sampleTime
            Self.log.notice("playback clock anchored sampleTime=\(playerTime.sampleTime, privacy: .public)")
        }
        return playerTime
    }
}
// ReadAloudConfigChange (483) + ReadAloudResampling (482) — pure helpers — split into
// ReadAloudConfigChange.swift / ReadAloudResampling.swift (one type per file; ≤400-line cap).
