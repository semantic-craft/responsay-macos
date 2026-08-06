import SwiftUI
import OSLog
import ResponsayCore

@MainActor
@Observable
final class ReadAloudController: ReadAloudStoppable {
    enum Mode: Equatable { case idle, reading, repeating }

    // internal(set): the +Playback extension (sibling file) updates these during playback.
    var activeIndex: Int?
    var isPlaying = false
    var isPreparing = false
    private(set) var lastErrorMessage: String?
    /// 497: set when a read fell back to a non-selected provider, so the UI can tell the
    /// user the voice changed. nil when the selected engine spoke.
    private(set) var activeVoiceNotice: String?
    private(set) var mode: Mode = .idle
    private let transactions = ReadAloudTransactionManager()
    /// Read-only forwarder onto the transaction manager (07-05). The manager owns request identity;
    /// callers only ever read the current tx (tests + `resume()`) — they never mutate it directly.
    var currentTransaction: ReadAloudTransaction? { transactions.current }
    var speed: Double = 1.0
    /// Cross-surface single-flight (481). Defaults to the shared coordinator so all
    /// surfaces single-flight in production; tests inject a private coordinator.
    var coordinator: ReadAloudCoordinator? = .shared
    /// 495: cache composed audio so re-reading the same standard sentence skips synthesis.
    /// Coach turns this on (stable, repeatable lines); Ask Anything leaves it off.
    var cachesComposedAudio = false
    private let composeCache = ReadAloudComposeCache()

    var source: (any ReadAloudSource)?   // internal: the +Playback extension mutates it
    private var loopsRemaining = 0
    private var task: Task<Void, Never>?
    var highlightTask: Task<Void, Never>?   // internal: cancelled by the +Playback extension
    private let tick: TimeInterval = 0.05

    let player: any ReadAloudAudioPlaying   // internal: used by the +Playback extension
    var makeSynthesizer: () throws -> any SpeechSynthesizer = {
        try TTSEngine.selected.makeSynthesizer()
    }
    var makeFallbackAttempts: (() -> [TTSFallbackAttempt])?
    var makeStreamingSynthesizer: () throws -> (any StreamingSpeechSynthesizer)? = {
        try TTSEngine.selected.makeStreamingSynthesizer()
    }
    var onReadingFinished: (@MainActor () -> Void)?
    var preflightForPlayback: @MainActor (ReadAloudTransaction) -> (mutedBefore: Bool, mutedAfter: Bool) = { tx in
        let before = AudioOutputMuter.shared.isOutputMutedByApp
        AudioOutputMuter.shared.disengage()
        let after = AudioOutputMuter.shared.isOutputMutedByApp
        Diag.tts(.info, "朗读 preflight", fields: [
            "requestID": tx.requestID.uuidString,
            "traceID": tx.traceID,
            "appOutputMutedBefore": String(before),
            "appOutputMutedAfter": String(after),
        ])
        return (before, after)
    }
    private let composer = ReadAloudComposer()
    static let log = Logger(   // internal: used by the +Playback extension
        subsystem: "com.semanticcraft.responsay.mac", category: "ReadAloud")

    /// Engine playback-anchor deadline (197 / P0-08). internal: used by the +Playback extension.
    static let anchorTimeout: TimeInterval = 0.35
    static let playbackFailedMessage = "朗读失败：音频播放没有启动。"
    static let noPlayableSpeechMessage = "朗读失败：没有生成可播放的语音。"

    init(player: any ReadAloudAudioPlaying = AudioReadAloudPlayer()) {
        self.player = player
    }

    func toggleRead(_ analysis: ProsodyAnalysis) {
        if isPlaying {
            Self.log.notice("toggle read: pause")
            pause()
            return
        }
        lastErrorMessage = nil
        activeVoiceNotice = nil
        if !isPreparing, mode == .reading, let source, !source.timeline.isEmpty {
            Self.log.notice("toggle read: resume")
            resume(); return   // resume after a pause
        }
        resetForNewRequest()
        coordinator?.activate(self)   // 481: cancel any other surface's read
        let tx = transactions.begin()
        let preflight = preflightForPlayback(tx)
        mode = .reading
        isPreparing = true
        let timeline = ReadAloudTimeline.build(analysis)
        source = EstimatedReadAloudSource(timeline: timeline)
        activeIndex = nil
        task?.cancel()
        highlightTask?.cancel()
        highlightTask = nil
        Self.log.notice("toggle read: start traceID=\(tx.traceID, privacy: .public) mutedBefore=\(preflight.mutedBefore, privacy: .public) mutedAfter=\(preflight.mutedAfter, privacy: .public)")
        task = Task { @MainActor [weak self] in
            await self?.startReading(analysis, tx: tx)
        }
    }

    func repeatRead(_ analysis: ProsodyAnalysis, count: Int = 3) {
        stop()
        coordinator?.activate(self)   // 481: cancel any other surface's read
        lastErrorMessage = nil
        activeVoiceNotice = nil
        let tx = transactions.begin()
        let preflight = preflightForPlayback(tx)
        mode = .repeating
        isPreparing = true
        loopsRemaining = max(1, count)
        let timeline = ReadAloudTimeline.build(analysis)
        source = EstimatedReadAloudSource(timeline: timeline)
        activeIndex = nil
        Self.log.notice("repeat read: start traceID=\(tx.traceID, privacy: .public) loops=\(self.loopsRemaining, privacy: .public) mutedBefore=\(preflight.mutedBefore, privacy: .public) mutedAfter=\(preflight.mutedAfter, privacy: .public)")
        task = Task { @MainActor [weak self] in
            await self?.startRepeating(analysis, tx: tx)
        }
    }

    /// 屏底浮窗朗读控制条用:在播放/暂停之间切换(不重新合成)。仅对 .reading 有意义。
    func pauseOrResume() {
        if isPlaying {
            pause()
        } else if mode == .reading, let source, !source.timeline.isEmpty {
            resume()
        }
    }

    /// True while a 朗读 is preparing or playing — drives the floating control panel's visibility.
    var isActive: Bool { isPreparing || isPlaying || mode != .idle }

    func stop() {
        task?.cancel()
        task = nil
        highlightTask?.cancel()
        highlightTask = nil
        source?.stop()
        source = nil
        isPreparing = false
        isPlaying = false
        lastErrorMessage = nil
        activeVoiceNotice = nil
        activeIndex = nil
        mode = .idle
        loopsRemaining = 0
        transactions.clear()
        coordinator?.resign(self)   // 481: release the cross-surface active slot
    }

    @discardableResult
    func applyHighlight(at elapsed: TimeInterval) -> Bool {
        let timeline = source?.timeline ?? []
        activeIndex = ReadAloudTimeline.activeIndex(at: elapsed, in: timeline)
        return elapsed < ReadAloudTimeline.totalDuration(timeline)
    }

    private func startReading(_ analysis: ProsodyAnalysis, tx: ReadAloudTransaction) async {
        let engineTitle = TTSEngine.selected.title
        let diag = ReadAloudDiagnosticContext(transaction: tx, text: analysis.text)
        Diag.tts(.info, "朗读 start", fields: diag.fields(
            mode: "reading", phase: "start", attempt: 0,
            provider: engineTitle, fallback: "none", result: "started"))
        do {
            if let streamer = try makeStreamingSynthesizer() {
                Self.log.notice("read streaming available engine=\(engineTitle, privacy: .public)")
                try await startStreamingPlayback(analysis, streamer, tx: tx, diag: diag)
                return
            }
            Self.log.notice("read streaming unavailable, using composed synth engine=\(engineTitle, privacy: .public)")
        } catch {
            guard isCurrent(tx, phase: "streamingFallback") else { return }
            let code = ReadAloudDiagnostics.errorCode(error)
            Diag.tts(.error, "streaming failed -> fallback synth", fields: diag.fields(
                mode: "reading", phase: "streaming", attempt: 0,
                provider: engineTitle, fallback: "nonStreaming", result: "failed",
                extra: ["errorCode": code]), error: code)
            Self.log.info("朗读 streaming failed, trying fallback synth: \(code, privacy: .public)")
            guard !Task.isCancelled else { return }
            source = EstimatedReadAloudSource(timeline: ReadAloudTimeline.build(analysis))
        }
        let composed = await composeRealAudio(analysis, modeName: "reading", diag: diag)
        guard isCurrent(tx, phase: "synthDone"), !Task.isCancelled else {
            Self.log.notice("read synth cancelled engine=\(engineTitle, privacy: .public)")
            return
        }
        if let composed, !composed.timeline.isEmpty {
            let underway = await playComposedOrEmergency(
                composed, mode: .reading(engineTitle: engineTitle, chunks: composed.chunks.count),
                tx: tx, diag: diag)
            guard underway else { return }
        } else {
            Self.log.error("read synth returned no playable timeline engine=\(engineTitle, privacy: .public)")
            failVisible(Self.noPlayableSpeechMessage)
            return
        }
        guard isCurrent(tx, phase: "play"), !Task.isCancelled else { return }
        play(tx)
    }

    private func resetForNewRequest() {
        task?.cancel()
        task = nil
        highlightTask?.cancel()
        highlightTask = nil
        source?.stop()
        player.stop()
        source = nil
        isPreparing = false
        isPlaying = false
        activeIndex = nil
        mode = .idle
        loopsRemaining = 0
    }

    func isCurrent(_ tx: ReadAloudTransaction, phase: String) -> Bool {   // internal: +Playback
        transactions.isCurrent(tx, phase: phase)   // forwards to the manager (07-05)
    }

    private func startRepeating(_ analysis: ProsodyAnalysis, tx: ReadAloudTransaction) async {
        let diag = ReadAloudDiagnosticContext(transaction: tx, text: analysis.text)
        if let composed = await composeRealAudio(analysis, modeName: "repeating", diag: diag),
           isCurrent(tx, phase: "repeatSynthDone"), !Task.isCancelled,
           !composed.timeline.isEmpty {
            let underway = await playComposedOrEmergency(
                composed, mode: .repeating(loops: loopsRemaining), tx: tx, diag: diag)
            guard underway else { return }
        } else {
            Self.log.error("repeat synth returned no playable timeline engine=\(TTSEngine.selected.title, privacy: .public)")
            failVisible(Self.noPlayableSpeechMessage)
            return
        }
        guard isCurrent(tx, phase: "repeatPlay"), !Task.isCancelled else { return }
        play(tx)
    }

    private func composeRealAudio(
        _ analysis: ProsodyAnalysis,
        modeName: String,
        diag: ReadAloudDiagnosticContext
    ) async -> ComposedReadAloud? {
        let attempts = makeFallbackAttempts?()
            ?? TTSFallbackAttempt.attempts(makeSelected: makeSynthesizer)
        let fallbackComposer = ReadAloudFallbackComposer(
            composer: composer, attempts: attempts, speed: speed)
        // 495: cache composed audio for cacheable (Coach) reads; Ask passes no key.
        let key = cachesComposedAudio ? composeCacheKey(for: analysis.text) : nil
        let outcome = await fallbackComposer.compose(
            analysis.text, modeName: modeName, diag: diag, cache: composeCache, cacheKey: key)
        // 497: surface the voice change when a fallback provider was used.
        if let outcome {
            activeVoiceNotice = outcome.isFallback ? Self.voiceNotice(provider: outcome.providerTitle) : nil
        }
        return outcome?.audio
    }

    /// 495: cache identity for one composed utterance. Includes engine + voice + speed so
    /// switching any of them misses (no stale-voice replay).
    private func composeCacheKey(for text: String) -> String {
        let voice = TTSEngine.selected.selectedVoiceID ?? "default"
        return "\(ReadAloudDiagnostics.hash(text))|\(TTSEngine.selected.title)|\(voice)|\(speed)"
    }

    /// 497: user-facing notice that a fallback voice is speaking.
    private static func voiceNotice(provider: String) -> String {
        "已回退到 \(provider) 朗读(音色可能不同)"
    }

    /// 朗读 vs 复读 differ only in diagnostics; this bundles those differences so the
    /// recovery ladder itself lives in one place (`playComposedOrEmergency`).
    private enum PlaybackLogMode {
        case reading(engineTitle: String, chunks: Int)
        case repeating(loops: Int)

        var name: String { self.isReading ? "reading" : "repeating" }
        var isReading: Bool { if case .reading = self { true } else { false } }
        var provider: String {
            switch self {
            case .reading(let title, _): title
            case .repeating: TTSEngine.selected.title
            }
        }
        var anchoredPhase: String { isReading ? "playbackAnchored" : "repeatPlaybackAnchored" }
        var failedPhase: String { isReading ? "playbackFailed" : "repeatPlaybackFailed" }
        var anchoredTitle: String { isReading ? "synth done" : "复读 synth done" }
        var failedTitle: String { isReading ? "playback failed" : "复读 playback failed" }
        func anchoredExtra(durationMs: Int) -> [String: String] {
            switch self {
            case .reading(_, let chunks): ["durationMs": String(durationMs), "chunks": String(chunks)]
            case .repeating(let loops): ["durationMs": String(durationMs), "loops": String(loops)]
            }
        }
    }

    /// Shared recovery ladder for 朗读 + 复读 (484): engine reset-retry
    /// (`startAnchoredPlayback`) → file emergency → visible error. Installs the
    /// player-backed source on success and returns whether playback is underway; the
    /// caller drives `play(tx)`. Returns false on a stale transaction or a visible failure
    /// (both mean "do not play").
    private func playComposedOrEmergency(
        _ composed: ComposedReadAloud,
        mode: PlaybackLogMode,
        tx: ReadAloudTransaction,
        diag: ReadAloudDiagnosticContext
    ) async -> Bool {
        let durationMs = Int(composed.totalDuration * 1000)
        do {
            try await startAnchoredPlayback(composed)
            guard isCurrent(tx, phase: mode.anchoredPhase) else { return false }
            source = PlayerReadAloudSource(
                timeline: composed.timeline, player: player, composed: composed)
            Diag.tts(.info, mode.anchoredTitle, fields: diag.fields(
                mode: mode.name, phase: "playback", attempt: 0,
                provider: mode.provider, fallback: "none", result: "anchored",
                extra: mode.anchoredExtra(durationMs: durationMs)))
            return true
        } catch {
            guard isCurrent(tx, phase: mode.failedPhase) else { return false }
            let code = ReadAloudDiagnostics.errorCode(error)
            Diag.tts(.error, mode.failedTitle, fields: diag.fields(
                mode: mode.name, phase: "playback", attempt: 0,
                provider: mode.provider, fallback: "fileEmergency", result: "failed",
                extra: ["errorCode": code]), error: code)
            Self.log.error("\(mode.name, privacy: .public) player failed: \(code, privacy: .public)")
            if playEmergency(composed, modeName: mode.name, diag: diag) { return true }
            failVisible(Self.playbackFailedMessage)
            return false
        }
    }

    private func failVisible(_ message: String) {
        player.stop()
        source = nil
        isPreparing = false
        isPlaying = false
        activeIndex = nil
        mode = .idle
        loopsRemaining = 0
        lastErrorMessage = message
        transactions.clear()
    }

    private func resume() {
        source?.resume()
        guard let tx = currentTransaction else { return }
        play(tx)
    }

    private func pause() {
        task?.cancel(); task = nil
        highlightTask?.cancel(); highlightTask = nil
        source?.pause()
        isPreparing = false
        isPlaying = false
    }

    func play(_ tx: ReadAloudTransaction) {   // internal: called by the +Playback extension
        guard isCurrent(tx, phase: "highlightStart") else { return }
        guard let source, !source.timeline.isEmpty else {
            Self.log.error("highlight play skipped: empty source")
            isPreparing = false
            return
        }
        isPreparing = false
        isPlaying = true
        highlightTask?.cancel()
        highlightTask = Task { @MainActor [weak self] in
            while let self, self.isPlaying, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard self.isPlaying, !Task.isCancelled,
                      self.isCurrent(tx, phase: "highlightTick")
                else { break }
                self.step(tx)
            }
        }
    }

    private func step(_ tx: ReadAloudTransaction) {
        guard isCurrent(tx, phase: "highlightStep") else { return }
        guard let source else { return }
        source.advance(by: tick, speed: speed)
        if source.isFinished {
            if mode == .repeating, loopsRemaining > 1 {
                loopsRemaining -= 1
                source.reset()
            } else {
                let wasReading = mode == .reading
                let callback = wasReading ? onReadingFinished : nil
                stop()
                callback?()
                return
            }
        }
        activeIndex = ReadAloudTimeline.activeIndex(at: source.elapsed, in: source.timeline)
    }
}
