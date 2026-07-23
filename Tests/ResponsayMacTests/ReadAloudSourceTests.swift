import XCTest
@testable import ResponsayMac
import ResponsayCore

/// 198 refactor — the estimated-clock source is now pure (no audio), so its clock
/// math is headless-testable. Test standard T1.
@MainActor
final class ReadAloudSourceTests: XCTestCase {
    private let twoWords = [
        TimedWord(text: "a", startTime: 0, endTime: 1),
        TimedWord(text: "b", startTime: 1, endTime: 2),
    ]

    func testAdvanceScalesBySpeedAndFinishesAtTotal() {
        let s = EstimatedReadAloudSource(timeline: twoWords)
        XCTAssertEqual(s.elapsed, 0)
        XCTAssertFalse(s.isFinished)
        s.advance(by: 0.5, speed: 1.0)
        XCTAssertEqual(s.elapsed, 0.5, accuracy: 1e-9)
        s.advance(by: 1.0, speed: 2.0)            // +1.0×2 → 2.5
        XCTAssertEqual(s.elapsed, 2.5, accuracy: 1e-9)
        XCTAssertTrue(s.isFinished)               // ≥ total (2)
    }

    func testPauseHaltsAdvanceResumeContinues() {
        let s = EstimatedReadAloudSource(timeline: [TimedWord(text: "x", startTime: 0, endTime: 5)])
        s.advance(by: 1, speed: 1)
        s.pause()
        s.advance(by: 1, speed: 1)                // ignored while paused
        XCTAssertEqual(s.elapsed, 1, accuracy: 1e-9)
        s.resume()
        s.advance(by: 1, speed: 1)
        XCTAssertEqual(s.elapsed, 2, accuracy: 1e-9)
    }

    func testResetReturnsToStart() {
        let s = EstimatedReadAloudSource(timeline: [TimedWord(text: "x", startTime: 0, endTime: 5)])
        s.advance(by: 3, speed: 1)
        s.reset()
        XCTAssertEqual(s.elapsed, 0)
        XCTAssertFalse(s.isFinished)
    }

    func testSpeedFlooredAtQuarter() {
        // Guards against a frozen highlight if speed is set absurdly low.
        let s = EstimatedReadAloudSource(timeline: [TimedWord(text: "x", startTime: 0, endTime: 5)])
        s.advance(by: 1, speed: 0)
        XCTAssertEqual(s.elapsed, 0.25, accuracy: 1e-9)
    }

    // MARK: - 301 · real-audio looping

    private func composedFixture() -> ComposedReadAloud {
        ComposedReadAloud(
            chunks: [SynthesizedSpeech(samples: [0, 0.1, 0], sampleRate: 24_000)],
            timeline: twoWords, totalDuration: 2)
    }

    func testPlayerSourceReset_reschedulesTheSameComposedAudio() {
        let player = MockAudioPlayer()
        let composed = composedFixture()
        let s = PlayerReadAloudSource(timeline: composed.timeline, player: player, composed: composed)
        player.isFinished = true            // loop boundary reached
        s.reset()
        XCTAssertEqual(player.playCalls.count, 1)          // schedule count: exactly one re-play
        XCTAssertEqual(player.playCalls.first, composed)   // …of the SAME buffers
        XCTAssertFalse(s.isFinished)                       // clock restarted
        s.reset()
        XCTAssertEqual(player.playCalls.count, 2)          // each loop re-schedules once
    }

    func testPlayerSourceReset_isNoopOnStreamingPath() {
        // A finished live stream has no re-schedulable buffers — reset must not
        // attempt playback (the loop then just ends early, by design).
        let player = MockAudioPlayer()
        let s = PlayerReadAloudSource(timeline: twoWords, player: player, composed: nil)
        s.reset()
        XCTAssertTrue(player.playCalls.isEmpty)
    }

    func testRepeatRead_attemptsRealSynthesis_andStopsOnFailure() async throws {
        // 301: 复读 tries to synthesize a real voice; P0 must not run a silent
        // estimated loop when synthesis fails.
        let controller = ReadAloudController()
        let attempted = Flag()
        controller.makeStreamingSynthesizer = { nil }
        controller.makeFallbackAttempts = {
            attempted.set()
            return [
                TTSFallbackAttempt(target: .selected, title: "selected") {
                    throw TTSError.synthesisFailed("stub: no engine in tests")
                }
            ]
        }
        // Plenty of loops so the assertions race nothing.
        controller.repeatRead(.followReadSeed(from: "Hello world from the loop"), count: 99)
        for _ in 0..<200 where !attempted.value {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(attempted.value)                  // real synthesis was attempted
        XCTAssertEqual(controller.mode, .idle)
        XCTAssertFalse(controller.isPlaying)
        XCTAssertNotNil(controller.lastErrorMessage)
        controller.stop()
    }

    // 483: re-schedule on a config change only when engine-path audio was live and a
    // composed utterance is retained.
    func testConfigChangeReplayDecision() {
        XCTAssertTrue(ReadAloudConfigChange.shouldReplay(wasActive: true, hasUtterance: true))
        XCTAssertFalse(ReadAloudConfigChange.shouldReplay(wasActive: false, hasUtterance: true))   // idle
        XCTAssertFalse(ReadAloudConfigChange.shouldReplay(wasActive: true, hasUtterance: false))   // streaming/emergency
        XCTAssertFalse(ReadAloudConfigChange.shouldReplay(wasActive: false, hasUtterance: false))
    }

    // 482: resampled output-buffer capacity math (24k ↔ 48k / 44.1k).
    func testResamplingOutputFrameCount() {
        XCTAssertEqual(ReadAloudResampling.outputFrameCount(sourceFrames: 100, sourceRate: 24_000, targetRate: 48_000), 200)
        XCTAssertEqual(ReadAloudResampling.outputFrameCount(sourceFrames: 240, sourceRate: 24_000, targetRate: 44_100), 441)
        XCTAssertEqual(ReadAloudResampling.outputFrameCount(sourceFrames: 100, sourceRate: 48_000, targetRate: 24_000), 50)
        XCTAssertEqual(ReadAloudResampling.outputFrameCount(sourceFrames: 0, sourceRate: 24_000, targetRate: 48_000), 0)
        XCTAssertEqual(ReadAloudResampling.outputFrameCount(sourceFrames: 100, sourceRate: 0, targetRate: 48_000), 0)
    }

    // 495: compose cache is LRU — getting an entry makes it most-recently-used.
    func testComposeCacheEvictsLeastRecentlyUsed() {
        let cache = ReadAloudComposeCache(capacity: 2)
        func composed(_ tag: String) -> ComposedReadAloud {
            ComposedReadAloud(
                chunks: [], timeline: [TimedWord(text: tag, startTime: 0, endTime: 1)], totalDuration: 1)
        }
        cache.set("k1", composed("1"))
        cache.set("k2", composed("2"))
        XCTAssertNotNil(cache.get("k1"))   // touch k1 → k2 is now LRU
        cache.set("k3", composed("3"))     // evicts k2

        XCTAssertNil(cache.get("k2"))
        XCTAssertNotNil(cache.get("k1"))
        XCTAssertNotNil(cache.get("k3"))
    }
}

/// MainActor-safe mutable flag for closure capture under Swift 6 concurrency.
@MainActor
private final class Flag {
    private(set) var value = false
    func set() { value = true }
}

@MainActor
private final class MockAudioPlayer: ReadAloudAudioPlaying {
    var elapsed: TimeInterval = 0
    var isFinished = false
    private(set) var playCalls: [ComposedReadAloud] = []

    func play(_ composed: ComposedReadAloud) throws {
        playCalls.append(composed)
        elapsed = 0
        isFinished = false
    }
    func waitForPlaybackAnchor(timeout: TimeInterval) async -> Bool { true }
    func playFileEmergency(_ composed: ComposedReadAloud) -> Bool { false }
    func beginStreaming(sampleRate: Double) throws {}
    func appendStreaming(_ speech: SynthesizedSpeech) -> TimeInterval { 0 }
    func endStreaming() {}
    func pause() {}
    func resume() {}
    func stop() {}
}
