import XCTest
import AVFoundation
import ResponsayCore
@testable import ResponsayMac

@MainActor
final class ReadAloudRecoveryTests: XCTestCase {
    @MainActor
    private final class Transport {
        var time: Double? = 0
        var schedules: [(Double, Bool)] = []
        var fails = false
        var stops = 0
        lazy var state = ReadAloudConfigChange(clock: { self.time }, schedule: { _, offset, playing in
            if self.fails { throw TTSError.synthesisFailed("test output unavailable") }
            self.schedules.append((offset, playing))
            self.time = nil
        }, halt: { self.stops += 1; self.time = nil })
    }
    private var audio: ComposedReadAloud {
        ComposedReadAloud(chunks: [SynthesizedSpeech(samples: Array(repeating: 0.2, count: 100), sampleRate: 10)],
                          timeline: [], totalDuration: 10)
    }

    func testPlayingSwitchPreservesOffsetAndRepeatedNotifications() throws {
        let t = Transport()
        try t.state.start(audio)
        t.time = 3
        XCTAssertEqual(t.state.elapsed, 3)
        t.time = nil // device invalidates render time before notification
        let generation = t.state.generation
        t.state.recover(generation: generation)
        XCTAssertEqual(t.schedules.last?.0, 3)
        XCTAssertEqual(t.schedules.last?.1, true)
        t.state.recover(generation: generation)
        XCTAssertEqual(t.schedules.last?.0, 3)
        t.time = 2 // new render clock (at any output sample rate)
        XCTAssertEqual(t.state.elapsed, 5)
        t.state.stop()
    }

    func testPauseBeforeQueuedRecoveryStaysPausedAndResumeContinues() throws {
        let t = Transport()
        try t.state.start(audio)
        let generation = t.state.generation
        t.time = 4
        t.state.pause()
        t.state.recover(generation: generation)
        XCTAssertEqual(t.schedules.last?.0, 4)
        XCTAssertEqual(t.schedules.last?.1, false)
        t.time = 8
        XCTAssertEqual(t.state.elapsed, 4)
        t.time = 0
        t.state.resume()
        t.time = 1
        XCTAssertEqual(t.state.elapsed, 5)
        t.state.stop()
    }

    func testStopAndNewPlaybackInvalidateQueuedRecovery() throws {
        let t = Transport()
        try t.state.start(audio)
        let old = t.state.generation
        t.state.stop()
        t.state.recover(generation: old)
        XCTAssertEqual(t.schedules.count, 1)
        try t.state.start(audio)
        t.state.recover(generation: old)
        XCTAssertEqual(t.schedules.count, 2)
        XCTAssertEqual(t.state.elapsed, 0)
        t.state.stop()
    }

    func testRecoveryFailureStopsAndReportsOnce() throws {
        let t = Transport()
        try t.state.start(audio)
        var failures = 0
        t.state.onFailure = { _ in failures += 1 }
        let generation = t.state.generation
        t.fails = true
        t.state.recover(generation: generation)
        t.state.recover(generation: generation)
        XCTAssertEqual(failures, 1)
        XCTAssertEqual(t.state.intent, .stopped)
        XCTAssertNil(t.state.composed)
    }

    func testMissingRecoveryClockTerminatesButPausedRecoveryDoesNotTimeout() throws {
        let t = Transport()
        try t.state.start(audio)
        var failures = 0
        t.state.onFailure = { _ in failures += 1 }
        t.state.pause()
        t.state.recover(generation: t.state.generation)
        t.state.checkRecoveryClock(now: .distantFuture)
        XCTAssertEqual(failures, 0)
        t.state.resume()
        t.time = 0 // a stationary anchor is not a recovered playback clock
        t.state.checkRecoveryClock(now: .distantFuture)
        XCTAssertEqual(failures, 1)
        XCTAssertEqual(t.state.intent, .stopped)
    }

    func testTrimmingAcrossChunksUsesSourceRatesAndKeepsSilentTail() {
        let chunks = [SynthesizedSpeech(samples: [1, 2, 3, 4], sampleRate: 4),
                      SynthesizedSpeech(samples: [5, 6, 0, 0], sampleRate: 2)]
        let remaining = ReadAloudConfigChange.remainingChunks(chunks, after: 2)
        XCTAssertEqual(remaining, [SynthesizedSpeech(samples: [0, 0], sampleRate: 2)])
        XCTAssertTrue(ReadAloudConfigChange.remainingChunks(chunks, after: 3).isEmpty)
        for rate in [24_000, 44_100, 48_000] {
            let chunk = SynthesizedSpeech(samples: Array(repeating: 1, count: rate), sampleRate: rate)
            XCTAssertEqual(ReadAloudConfigChange.remainingChunks([chunk], after: 0.5)[0].samples.count, rate / 2)
        }
    }

    func testRemainingPCMConversionKeepsDurationAndSilenceWithoutOpeningDevice() throws {
        let source = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                                sampleRate: 24_000, channels: 1, interleaved: false))
        let chunks = [SynthesizedSpeech(samples: Array(repeating: 0, count: 12_000), sampleRate: 24_000)]
        let audio = ComposedReadAloud(chunks: chunks, timeline: [], totalDuration: 0.5)
        for invalid in [0.0, -1.0, Double.nan, Double.infinity] {
            XCTAssertThrowsError(try AudioReadAloudPlayer.makeScheduledBuffers(
                for: audio, sourceFormat: source, outputRate: invalid))
        }
        for rate in [24_000.0, 44_100.0, 48_000.0] {
            let buffers = try AudioReadAloudPlayer.makeScheduledBuffers(for: audio, sourceFormat: source, outputRate: rate)
            XCTAssertFalse(buffers.buffers.isEmpty)
            XCTAssertEqual(buffers.format.sampleRate, rate)
            XCTAssertEqual(Double(buffers.totalFrames) / rate, 0.5, accuracy: 0.01)
        }
    }

    func testControllerRecoveryFailureClearsPlayingAndPreparation() async throws {
        let player = RecordingAudioPlayer()
        let reader = ReadAloudController(player: player)
        reader.coordinator = nil
        reader.preflightForPlayback = { _ in (false, false) }
        reader.makeStreamingSynthesizer = { nil }
        reader.makeFallbackAttempts = {
            [TTSFallbackAttempt(target: .selected, title: "test") { OneShotSynthesizer() }]
        }
        reader.toggleRead(.sample)
        for _ in 0..<100 where !reader.isPlaying { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(reader.isPlaying)
        player.onPlaybackFailure?(TTSError.synthesisFailed("test restart failed"))
        XCTAssertFalse(reader.isPlaying)
        XCTAssertFalse(reader.isPreparing)
        XCTAssertNil(reader.activeIndex)
        XCTAssertNil(reader.currentTransaction)
        XCTAssertEqual(reader.lastErrorMessage, ReadAloudController.playbackFailedMessage)
    }
}
