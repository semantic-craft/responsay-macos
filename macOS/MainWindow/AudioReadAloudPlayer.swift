import AVFoundation
import OSLog
import ResponsayCore

/// Plays a `ComposedReadAloud`'s chunks gaplessly on an `AVAudioPlayerNode` and
/// exposes the real playback `elapsed` time so `ReadAloudController` can drive the
/// word highlight from the audio clock instead of an estimate (issue 194).
///
/// Recovery math is covered without devices. Bluetooth transitions and audible
/// continuity still require real-Mac acceptance.
@MainActor
final class AudioReadAloudPlayer: ReadAloudAudioPlaying {
    private let engine: AVAudioEngine
    private let node = AVAudioPlayerNode()
    private var startSampleTime: AVAudioFramePosition?
    private var sampleRate: Double = 24_000
    private var totalDuration: TimeInterval = 0
    var onPlaybackFailure: ((Error) -> Void)?
    private var clockTask: Task<Void, Never>?
    private var outputObserver: ReadAloudOutputObserver?
    private lazy var recovery = ReadAloudConfigChange(
        clock: { [weak self] in self?.renderElapsed },
        schedule: { [weak self] audio, offset, playing in
            try self?.scheduleComposed(audio, offset: offset, playing: playing)
        },
        halt: { [weak self] in
            self?.node.stop()
            self?.engine.stop()
            self?.startSampleTime = nil
        })
    private nonisolated(unsafe) var configChangeObserver: NSObjectProtocol?
    private static let log = Logger(
        subsystem: "com.semanticcraft.responsay.mac", category: "ReadAloudAudio")

    init(engine: AVAudioEngine = AVAudioEngine()) {
        self.engine = engine
        engine.attach(node)
        recovery.onFailure = { [weak self] error in
            self?.clockTask?.cancel()
            self?.onPlaybackFailure?(error)
        }
        // 483: react to output-device / sample-rate changes (AirPods ↔ built-in ↔ HDMI).
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let generation = self.recovery.generation
                Task { @MainActor [weak self] in
                    self?.handleConfigurationChange(generation: generation)
                }
            }
        }

        outputObserver = ReadAloudOutputObserver { [weak self] in
            guard let self else { return }
            let generation = self.recovery.generation
            Task { @MainActor [weak self] in
                self?.handleConfigurationChange(generation: generation)
            }
        }
    }

    deinit {
        clockTask?.cancel()
        if let configChangeObserver { NotificationCenter.default.removeObserver(configChangeObserver) }
    }

    /// Elapsed playback time in seconds (0 before start, clamped to total).
    var elapsed: TimeInterval {
        if let emergencyPlayer { return min(emergencyPlayer.currentTime, totalDuration) }  // 484
        if recovery.composed != nil { return recovery.elapsed }
        if streamState.generation != nil {
            streamState.observe(renderElapsed)
            return streamState.position
        }
        return renderElapsed ?? 0
    }

    private var renderElapsed: TimeInterval? {
        guard let playerTime = anchorIfAvailable() else { return nil }
        guard let startSampleTime else { return 0 }
        let frames = playerTime.sampleTime - startSampleTime
        let seconds = Double(max(0, frames)) / sampleRate
        return min(seconds, totalDuration)
    }

    var isFinished: Bool {
        // 484: the file emergency player reports finish via `isPlaying` going false.
        if let emergencyPlayer { return !emergencyPlayer.isPlaying }
        if streamState.generation != nil {
            _ = elapsed
            return streamState.isFinished
        }
        return elapsed >= totalDuration && totalDuration > 0
    }

    /// Schedule the composed chunks and start playing. Throws if audio setup fails.
    func play(_ composed: ComposedReadAloud) throws {
        stop()
        try recovery.start(composed)
        clockTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard self?.recovery.composed != nil else { return }
                self?.recovery.checkRecoveryClock()
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
    }

    private func scheduleComposed(_ composed: ComposedReadAloud, offset: TimeInterval, playing: Bool) throws {
        guard composed.hasPlayableAudio, let first = composed.chunks.first else {
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
        guard outputRate.isFinite, outputRate > 0,
              engine.outputNode.outputFormat(forBus: 0).channelCount > 0 else {
            throw TTSError.synthesisFailed("音频输出设备格式无效")
        }
        let chunks = ReadAloudConfigChange.remainingChunks(composed.chunks, after: offset)
        guard composed.chunks.allSatisfy({ $0.sampleRate == first.sampleRate }) else {
            throw TTSError.synthesisFailed("音频分段采样率不一致")
        }
        let remaining = ComposedReadAloud(chunks: chunks, timeline: [], totalDuration: composed.totalDuration - offset)
        let prepared = try Self.makeScheduledBuffers(for: remaining, sourceFormat: sourceFormat, outputRate: outputRate)
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
        if playing { try engine.start() }
        let scheduled = prepared.buffers.count
        for buffer in prepared.buffers {
            node.scheduleBuffer(buffer, completionHandler: nil)
        }
        // A newly scheduled player timeline starts at frame zero, including when
        // the first render-time query arrives after playback has already advanced.
        startSampleTime = 0
        if playing { node.play() }
        Self.log.notice("scheduled buffers=\(scheduled, privacy: .public)")
    }

    func waitForPlaybackAnchor(timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let generation = recovery.generation
        while Date() < deadline {
            guard !Task.isCancelled, generation == recovery.generation else { return false }
            if anchorIfAvailable() != nil { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        Self.log.error("play failed: playback anchor timed out")
        return false
    }

    func pause() {
        if let emergencyPlayer { emergencyPlayer.pause(); return }  // 484
        recovery.pause()
        node.pause()
    }
    func resume() {
        if let emergencyPlayer { emergencyPlayer.play(); return }  // 484
        if recovery.composed != nil {
            guard recovery.intent == .paused else { return }
            recovery.resume()
            do { if !engine.isRunning { try engine.start() }; node.play() }
            catch { recovery.stop(); onPlaybackFailure?(error) }
            return
        }
        if streamFormat != nil { node.play() }
    }

    func stop() {
        clockTask?.cancel()
        clockTask = nil
        recovery.stop()
        emergencyPlayer?.stop()   // 484
        emergencyPlayer = nil
        startSampleTime = nil
        totalDuration = 0
        streamState.stop()
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

    private var streamState = ReadAloudStreamState()
    private var accumulated: TimeInterval = 0
    private var streamFormat: AVAudioFormat?

    /// Begin a streaming session (issue 197): start the node and accept chunks as
    /// they arrive, for low time-to-first-audio. `elapsed` / `totalDuration` grow as
    /// chunks are appended (we don't know the full length up front).
    func beginStreaming(sampleRate: Double) throws {
        stop()
        guard outputObserver?.isRegistered == true else {
            throw TTSError.synthesisFailed("无法监听音频输出设备变化")
        }
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
        let output = engine.outputNode.outputFormat(forBus: 0)
        guard output.sampleRate.isFinite, output.sampleRate > 0, output.channelCount > 0 else {
            throw TTSError.synthesisFailed("音频输出设备格式无效")
        }
        streamFormat = format
        engine.connect(node, to: engine.mainMixerNode, format: format)
        node.volume = 1
        engine.mainMixerNode.outputVolume = 1
        engine.prepare()
        do { try engine.start() }
        catch { stop(); throw error }
        // Do not advance the player clock while waiting for the provider's first chunk.
        startSampleTime = 0
        streamState.begin(generation: recovery.generation)
        clockTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard self?.streamState.generation != nil else { return }
                _ = self?.elapsed
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
    }

    /// Schedule one streaming chunk on the player node; returns the new accumulated
    /// total duration. Buffers queue gaplessly behind whatever is already playing.
    @discardableResult
    func appendStreaming(_ speech: SynthesizedSpeech) -> TimeInterval {
        guard streamState.acceptsAudio, let format = streamFormat,
              let buffer = Self.buffer(from: speech.samples, format: format) else {
            Self.log.error("streaming append skipped: no active stream or empty buffer")
            return accumulated
        }
        let firstChunk = streamState.duration == 0
        node.scheduleBuffer(buffer, completionHandler: nil)
        if firstChunk { node.play() }
        streamState.append(duration: speech.duration)
        accumulated = streamState.duration
        totalDuration = accumulated
        Self.log.notice(
            "streaming chunk scheduled samples=\(speech.samples.count, privacy: .public) totalMs=\(Int(self.totalDuration * 1000), privacy: .public)"
        )
        return accumulated
    }

    /// No more chunks will arrive — the accumulated duration is now final.
    func endStreaming() {
        _ = elapsed
        streamState.end()
    }

    private func handleConfigurationChange(generation: UUID) {
        guard generation == recovery.generation else { return }
        if streamState.generation != nil {
            _ = elapsed
            guard streamState.configurationChanged(generation: generation) else { return }
            stop()
            onPlaybackFailure?(ReadAloudPlaybackFailure.outputChanged)
            return
        }
        recovery.recover(generation: generation)
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
