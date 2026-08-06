import XCTest
@testable import ResponsayMac

@MainActor
final class ReadAloudDocumentReaderSettingChangeTests: XCTestCase {
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
