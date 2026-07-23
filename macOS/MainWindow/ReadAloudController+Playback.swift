import Foundation
import ResponsayCore

// Playback mechanics for ReadAloudController: incremental streaming (197), anchored engine
// playback with reset-retry (483/485), and the 484 file-level emergency rung. Split out to keep
// the controller ≤400 lines; same type, so the reading/repeating orchestration calls these
// unqualified. The shared state they touch (player/source/highlightTask/isPlaying/isPreparing/
// activeIndex/log + play/isCurrent) is `internal` on the controller for this reason — matching
// the `QuickCaptureViewModel+X` split convention.
extension ReadAloudController {

    func startStreamingPlayback(
        _ analysis: ProsodyAnalysis,
        _ streamer: any StreamingSpeechSynthesizer,
        tx: ReadAloudTransaction,
        diag: ReadAloudDiagnosticContext
    ) async throws {
        activeIndex = nil
        try player.beginStreaming(sampleRate: Double(TTSAudio.defaultSampleRate))
        Diag.tts(.info, "streaming begin", fields: diag.fields(
            mode: "reading", phase: "streaming", attempt: 0,
            provider: TTSEngine.selected.title, fallback: "nonStreaming", result: "started"))
        var chunkCount = 0
        var anchored = false
        let text = analysis.text
        let rate = speed
        let streamStart = Date()           // 485: time-to-first-audio observability
        var firstChunkLatencyMs = 0
        do {
            for try await chunk in streamer.stream(text, speed: rate) {
                guard isCurrent(tx, phase: "streamingChunk"), !Task.isCancelled else { return }
                if chunkCount == 0 { firstChunkLatencyMs = Int(Date().timeIntervalSince(streamStart) * 1000) }
                player.appendStreaming(chunk)
                chunkCount += 1
                if !anchored {
                    anchored = await player.waitForPlaybackAnchor(timeout: Self.anchorTimeout)
                    guard isCurrent(tx, phase: "streamingAnchor") else { return }
                    guard anchored else { throw TTSError.synthesisFailed("语音播放未启动，请重试或换一个引擎。") }
                    source = PlayerReadAloudSource(
                        timeline: ReadAloudTimeline.build(analysis), player: player)
                    play(tx)
                }
            }
            player.endStreaming()
            guard chunkCount > 0 else {
                throw TTSError.providerReturnedNoAudio(provider: TTSEngine.selected.title)
            }
            Diag.tts(.info, "streaming done", fields: diag.fields(
                mode: "reading", phase: "streaming", attempt: 0,
                provider: TTSEngine.selected.title, fallback: "none", result: "success",
                extra: [
                    "chunks": String(chunkCount),
                    "firstChunkLatencyMs": String(firstChunkLatencyMs),
                ]))
        } catch {
            player.endStreaming()
            player.stop()
            source = nil
            highlightTask?.cancel()
            highlightTask = nil
            isPlaying = false
            isPreparing = true
            activeIndex = nil
            guard isCurrent(tx, phase: "streamingFailed") else { return }
            let code = ReadAloudDiagnostics.errorCode(error)
            Diag.tts(.error, "streaming failed", fields: diag.fields(
                mode: "reading", phase: "streaming", attempt: 0,
                provider: TTSEngine.selected.title, fallback: "nonStreaming", result: "failed",
                extra: ["chunks": String(chunkCount), "errorCode": code]), error: code)
            Self.log.error("streaming failed: \(code, privacy: .public)")
            throw error
        }
    }

    func startAnchoredPlayback(_ composed: ComposedReadAloud) async throws {
        for attempt in 1...2 {
            try player.play(composed)
            let waitStart = Date()                                        // 485
            let ok = await player.waitForPlaybackAnchor(timeout: Self.anchorTimeout)
            let anchorWaitMs = Int(Date().timeIntervalSince(waitStart) * 1000)
            if ok {
                Self.log.notice("playback anchored attempt=\(attempt, privacy: .public) anchorWaitMs=\(anchorWaitMs, privacy: .public)")
                return
            }
            player.stop()
            Self.log.error("playback anchor timeout attempt=\(attempt, privacy: .public) anchorWaitMs=\(anchorWaitMs, privacy: .public)")
        }
        throw TTSError.synthesisFailed("语音播放未启动，请重试或换一个引擎。")
    }

    /// 484: last rung of the playback-recovery ladder — the engine path failed both
    /// reset-retry attempts, so play the already-synthesized PCM via a file-level
    /// `AVAudioPlayer` that bypasses `AVAudioEngine`. Returns whether sound started; on
    /// success installs a player-backed source so the highlight loop runs. Called
    /// synchronously inside the playback `catch` (no `await`), so the transaction the
    /// caller already validated stays current. Apple system TTS cannot cover this — it
    /// reuses the same broken engine.
    func playEmergency(
        _ composed: ComposedReadAloud,
        modeName: String,
        diag: ReadAloudDiagnosticContext
    ) -> Bool {
        guard player.playFileEmergency(composed) else { return false }
        source = PlayerReadAloudSource(
            timeline: composed.timeline, player: player, composed: composed, isEmergency: true)
        Diag.tts(.info, "emergency playback", fields: diag.fields(
            mode: modeName, phase: "playback", attempt: 0,
            provider: "AVAudioPlayer", fallback: "none", result: "emergency",
            extra: ["durationMs": String(Int(composed.totalDuration * 1000))]))
        Self.log.notice("read fell back to file emergency player mode=\(modeName, privacy: .public)")
        return true
    }
}
