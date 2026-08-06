import XCTest
@testable import ResponsayMac
import ResponsayCore

@MainActor
final class ReadAloudDocumentReaderSettingChangeTests: XCTestCase {
    func testFirstSynthesizedChunkSetsTheStreamingSampleRate() async throws {
        let player = RecordingAudioPlayer()
        let reader = ReadAloudDocumentReader(player: player)
        defer { reader.stop() }
        reader.coordinator = nil
        reader.makeSynthesizer = { (SampleRateSynthesizer(sampleRate: 32_000), nil) }

        reader.read("This sentence is long enough to produce one stable synthesized chunk.")

        try await waitUntil { reader.phase == .playing }
        XCTAssertEqual(player.beginStreamingRates, [32_000])
    }

    func testCancelledPipelineCannotEndItsReplacementStream() async throws {
        let player = RecordingAudioPlayer()
        let reader = ReadAloudDocumentReader(player: player)
        defer { reader.stop() }
        reader.coordinator = nil
        var factoryCalls = 0
        reader.makeSynthesizer = {
            factoryCalls += 1
            if factoryCalls == 1 {
                return (DelayedSynthesizer(delayMs: 150), nil)
            }
            return (OneShotSynthesizer(), nil)
        }
        reader.read("This sentence keeps the first synthesis in flight while playback is restarted.")
        try await waitUntil { factoryCalls == 1 }

        reader.voiceDidChange()

        try await waitUntil { player.endStreamingCalls == 1 }
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(player.endStreamingCalls, 1)
    }

    func testVoiceChangeRestartsFromTheCurrentLineWhilePlaying() async throws {
        let player = RecordingAudioPlayer()
        let reader = ReadAloudDocumentReader(player: player)
        defer { reader.stop() }
        reader.coordinator = nil
        reader.makeSynthesizer = { (OneShotSynthesizer(), nil) }
        reader.read("This is the first sentence with enough text to remain separate. This is the second sentence too.")
        try await waitUntil { reader.phase == .playing }
        let line = try XCTUnwrap(reader.activeLine)
        let stopCalls = player.stopCalls

        reader.voiceDidChange()

        XCTAssertEqual(reader.phase, .preparing)
        XCTAssertEqual(reader.activeLine, line)
        XCTAssertGreaterThan(player.stopCalls, stopCalls)
    }

    func testVoiceChangeWhilePausedDefersRebuildUntilResume() async throws {
        let player = RecordingAudioPlayer()
        let reader = ReadAloudDocumentReader(player: player)
        defer { reader.stop() }
        reader.coordinator = nil
        reader.makeSynthesizer = { (OneShotSynthesizer(), nil) }
        reader.read("This sentence is long enough to start a stable playback state for the test.")
        try await waitUntil { reader.phase == .playing }
        reader.pauseOrResume()
        let stopCalls = player.stopCalls

        reader.voiceDidChange()

        XCTAssertEqual(reader.phase, .paused)
        XCTAssertEqual(player.stopCalls, stopCalls)

        reader.pauseOrResume()
        XCTAssertEqual(reader.phase, .preparing)
        XCTAssertGreaterThan(player.stopCalls, stopCalls)
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !condition(), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition())
    }
}

private actor SampleRateSynthesizer: SpeechSynthesizer {
    let sampleRate: Int

    init(sampleRate: Int) {
        self.sampleRate = sampleRate
    }

    func synthesize(_ text: String, speed: Double) async throws -> SynthesizedSpeech {
        SynthesizedSpeech(samples: [0, 0.2, -0.2, 0], sampleRate: sampleRate)
    }
}
