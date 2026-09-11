import AVFoundation
import XCTest
import ResponsayCore
@testable import ResponsayMac

/// Opt-in real speaker output, never run by ordinary CI. No microphone or provider calls.
/// Configuration notifications below are injected; Bluetooth acceptance is separate.
@MainActor
final class ReadAloudDeviceE2ETests: XCTestCase {
    private func setupPlayer() throws -> (AVAudioEngine, AudioReadAloudPlayer) {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_READ_ALOUD_DEVICE_E2E"] == "1",
                          "Real speaker E2E requires explicit opt-in")
        let engine = AVAudioEngine()
        return (engine, AudioReadAloudPlayer(engine: engine))
    }

    func testComposedRealOutputRecoversWithoutResettingClock() async throws {
        let (engine, player) = try setupPlayer()
        defer { player.stop() }
        try player.play(Self.composed)
        try await waitUntil { player.elapsed > 0.35 }
        let before = player.elapsed
        engine.stop() // emulate engine loss before its configuration notification
        NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: engine)
        try await waitUntil { engine.isRunning && player.elapsed > before + 0.2 }
        XCTAssertLessThan(player.elapsed, before + 1)
        XCTAssertFalse(player.isFinished)
    }

    func testPausedRealOutputRemainsPausedAcrossRecovery() async throws {
        let (engine, player) = try setupPlayer()
        defer { player.stop() }
        try player.play(Self.composed)
        try await waitUntil { player.elapsed > 0.3 }
        player.pause()
        let before = player.elapsed
        engine.stop()
        NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: engine)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(engine.isRunning)
        XCTAssertEqual(player.elapsed, before, accuracy: 0.01)
        player.resume()
        try await waitUntil { player.elapsed > before + 0.2 }
    }

    func testRealStreamBeforeFirstChunkFailsOnceAndRejectsLateAudio() async throws {
        let (engine, player) = try setupPlayer()
        defer { player.stop() }
        var failures = 0
        player.onPlaybackFailure = { _ in failures += 1 }
        try player.beginStreaming(sampleRate: 24_000)
        NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: engine)
        NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: engine)
        try await waitUntil { failures == 1 }
        XCTAssertFalse(engine.isRunning)
        XCTAssertEqual(player.appendStreaming(Self.tone), 0)
        let anchored = await player.waitForPlaybackAnchor(timeout: 0.05)
        XCTAssertFalse(anchored)
        XCTAssertEqual(failures, 1)
    }

    func testDocumentRealOutputDeviceFailureThenRetry() async throws {
        let (engine, player) = try setupPlayer()
        let reader = ReadAloudDocumentReader(player: player)
        reader.coordinator = nil
        reader.makeSynthesizer = { (DeviceToneSynthesizer(), nil) }
        defer { reader.stop() }
        reader.read("Synthetic audio verifies document playback failure and retry.")
        try await waitUntil { reader.phase == .playing && player.elapsed > 0.3 }
        NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: engine)
        try await waitUntil { reader.phase == .idle }
        XCTAssertFalse(engine.isRunning)
        XCTAssertTrue(reader.shouldShowControls)
        XCTAssertNotNil(reader.errorMessage)
        reader.pauseOrResume()
        try await waitUntil { reader.phase == .playing && player.elapsed > 0.25 }
        XCTAssertNil(reader.errorMessage)
        XCTAssertTrue(engine.isRunning)
    }

    func testControllerRealStreamingTailFailsThenRetries() async throws {
        let (engine, player) = try setupPlayer()
        let reader = ReadAloudController(player: player)
        reader.coordinator = nil
        reader.preflightForPlayback = { _ in (false, false) }
        reader.makeStreamingSynthesizer = { DeviceToneSynthesizer() }
        reader.makeFallbackAttempts = { XCTFail("Device failure must not trigger synthesis fallback"); return [] }
        defer { reader.stop() }
        reader.toggleRead(.sample)
        try await waitUntil { reader.isPlaying && player.elapsed > 0.25 }
        NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: engine)
        try await waitUntil { !reader.isActive }
        XCTAssertNotNil(reader.lastErrorMessage)
        reader.toggleRead(.sample)
        try await waitUntil { reader.isPlaying && player.elapsed > 0.25 }
        XCTAssertNil(reader.lastErrorMessage)
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<200 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition())
    }

    static var tone: SynthesizedSpeech {
        let radiansPerSample = 2.0 * Double.pi * 440.0 / 24_000.0
        let samples: [Float] = (0..<96_000).map { Float(sin(Double($0) * radiansPerSample) * 0.04) }
        return SynthesizedSpeech(samples: samples, sampleRate: 24_000)
    }
    private static var composed: ComposedReadAloud {
        ComposedReadAloud(chunks: [tone], timeline: [], totalDuration: 4)
    }
}

private struct DeviceToneSynthesizer: SpeechSynthesizer, StreamingSpeechSynthesizer {
    func synthesize(_ text: String, speed: Double) async throws -> SynthesizedSpeech {
        await ReadAloudDeviceE2ETests.tone
    }
    func stream(_ text: String, speed: Double) -> AsyncThrowingStream<SynthesizedSpeech, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(await ReadAloudDeviceE2ETests.tone)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
