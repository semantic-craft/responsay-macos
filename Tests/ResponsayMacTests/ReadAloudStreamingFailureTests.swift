import XCTest
import ResponsayCore
@testable import ResponsayMac

@MainActor
final class ReadAloudStreamingFailureTests: XCTestCase {
    func testConfigurationBeforeFirstChunkFailsOnceAndOldNotificationCannotFailRetry() {
        var state = ReadAloudStreamState()
        let old = UUID()
        state.begin(generation: old)
        XCTAssertTrue(state.configurationChanged(generation: old))
        XCTAssertFalse(state.configurationChanged(generation: old))
        XCTAssertFalse(state.acceptsAudio)
        let retry = UUID()
        state.begin(generation: retry)
        XCTAssertFalse(state.configurationChanged(generation: old))
        XCTAssertTrue(state.acceptsAudio)
        state.stop()
        XCTAssertFalse(state.configurationChanged(generation: retry))
    }

    func testQueuedTailRemainsFailureSensitiveUntilActuallyPlayed() {
        var state = ReadAloudStreamState()
        let generation = UUID()
        state.begin(generation: generation)
        state.append(duration: 2)
        state.observe(2)
        XCTAssertFalse(state.isFinished) // provider may still deliver more
        state.append(duration: 3)
        state.end()
        XCTAssertFalse(state.isFinished)
        XCTAssertTrue(state.configurationChanged(generation: generation))
        state.begin(generation: generation)
        state.append(duration: 2)
        state.observe(2)
        state.end()
        XCTAssertTrue(state.isFinished)
        XCTAssertFalse(state.configurationChanged(generation: generation))
        state.append(duration: 10)
        XCTAssertEqual(state.duration, 2)
    }

    func testFailureBeforeFirstChunkCancelsUpstreamAndAllowsRetry() async throws {
        let player = RecordingAudioPlayer()
        let first = ControlledReadAloudStream()
        let retry = ControlledReadAloudStream()
        let reader = makeReader(player: player, streams: [first, retry])
        defer { reader.stop() }
        reader.toggleRead(.sample)
        try await waitUntil { player.beginStreamingRates.count == 1 }
        player.onPlaybackFailure?(ReadAloudPlaybackFailure.outputChanged)
        try await waitUntil { first.cancellationCount == 1 }
        XCTAssertFalse(reader.isActive)
        XCTAssertFalse(reader.isPreparing)
        XCTAssertEqual(reader.lastErrorMessage, ReadAloudPlaybackFailure.outputChanged.localizedDescription)
        first.yield()
        first.finish()
        XCTAssertEqual(player.appendStreamingCalls, 0)
        reader.toggleRead(.sample)
        try await waitUntil { player.beginStreamingRates.count == 2 }
        retry.yield()
        try await waitUntil { reader.isPlaying }
        XCTAssertNil(reader.lastErrorMessage)
        XCTAssertEqual(player.appendStreamingCalls, 1)
        XCTAssertTrue(player.playCalls.isEmpty) // no whole-text fallback on device failure
    }

    func testDeviceFailureWhileAwaitingAnchorCancelsProviderAndEndsPreparation() async throws {
        let player = RecordingAudioPlayer()
        player.anchorDelay = .seconds(30)
        let stream = ControlledReadAloudStream()
        let reader = makeReader(player: player, streams: [stream])
        defer { reader.stop() }
        reader.toggleRead(.sample)
        try await waitUntil { player.beginStreamingRates.count == 1 }
        stream.yield()
        try await waitUntil { player.appendStreamingCalls == 1 }
        XCTAssertTrue(reader.isPreparing)
        player.onPlaybackFailure?(ReadAloudPlaybackFailure.outputChanged)
        try await waitUntil { stream.cancellationCount == 1 }
        XCTAssertFalse(reader.isPreparing)
        XCTAssertFalse(reader.isPlaying)
        XCTAssertNotNil(reader.lastErrorMessage)
        XCTAssertNil(reader.currentTransaction)
    }

    func testPlayingFailureDoesNotClearReplacementWhenOldLoopUnwinds() async throws {
        let player = RecordingAudioPlayer()
        let first = ControlledReadAloudStream()
        let retry = ControlledReadAloudStream()
        let reader = makeReader(player: player, streams: [first, retry])
        defer { reader.stop() }
        reader.toggleRead(.sample)
        try await waitUntil { player.beginStreamingRates.count == 1 }
        first.yield()
        try await waitUntil { reader.isPlaying }
        player.onPlaybackFailure?(ReadAloudPlaybackFailure.outputChanged)
        reader.toggleRead(.sample) // replacement begins before cancelled iterator resumes
        try await waitUntil { player.beginStreamingRates.count == 2 }
        let stops = player.stopCalls
        let ends = player.endStreamingCalls
        first.yield()
        first.finish()
        retry.yield()
        try await waitUntil { reader.isPlaying && first.cancellationCount == 1 }
        XCTAssertEqual(player.stopCalls, stops)
        XCTAssertEqual(player.endStreamingCalls, ends)
        XCTAssertEqual(player.appendStreamingCalls, 2)
        XCTAssertNil(reader.lastErrorMessage)
        XCTAssertNotNil(reader.currentTransaction)
    }

    func testImmediateStopPreventsPendingTaskFromStartingTheStream() async throws {
        let player = RecordingAudioPlayer()
        let reader = makeReader(player: player, streams: [ControlledReadAloudStream()])
        reader.toggleRead(.sample)
        reader.stop()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(player.beginStreamingRates.isEmpty)
        XCTAssertFalse(reader.isActive)
        XCTAssertNil(reader.lastErrorMessage)
    }

    func testUserStopBeforeFirstChunkCancelsWithoutFailureOrEndOnReplacement() async throws {
        let player = RecordingAudioPlayer()
        let first = ControlledReadAloudStream()
        let retry = ControlledReadAloudStream()
        let reader = makeReader(player: player, streams: [first, retry])
        defer { reader.stop() }
        reader.toggleRead(.sample)
        try await waitUntil { player.beginStreamingRates.count == 1 }
        let stops = player.stopCalls
        reader.stop()
        XCTAssertGreaterThan(player.stopCalls, stops)
        XCTAssertNil(reader.lastErrorMessage)
        reader.toggleRead(.sample)
        try await waitUntil { player.beginStreamingRates.count == 2 && first.cancellationCount == 1 }
        first.finish()
        XCTAssertEqual(player.endStreamingCalls, 0)
        XCTAssertNil(reader.lastErrorMessage)
    }

    func testDocumentDeviceFailureCancelsInFlightSynthesisAndCanRetry() async throws {
        let player = RecordingAudioPlayer()
        let reader = ReadAloudDocumentReader(player: player)
        reader.coordinator = nil
        defer { reader.stop() }
        let synth = CancellationObservingLineSynthesizer()
        reader.makeSynthesizer = { (synth, nil) }
        reader.read("This is the first sentence with enough text to remain separate. This is the second sentence too.")
        try await waitUntil { reader.phase == .playing }
        for _ in 0..<100 where !(await synth.isWaiting) { try await Task.sleep(for: .milliseconds(10)) }
        let wasWaiting = await synth.isWaiting
        XCTAssertTrue(wasWaiting)
        player.onPlaybackFailure?(ReadAloudPlaybackFailure.outputChanged)
        for _ in 0..<100 where !(await synth.wasCancelled) { try await Task.sleep(for: .milliseconds(10)) }
        let wasCancelled = await synth.wasCancelled
        XCTAssertTrue(wasCancelled)
        XCTAssertEqual(reader.phase, .idle)
        XCTAssertTrue(reader.shouldShowControls)
        XCTAssertNil(reader.activeLine)
        XCTAssertEqual(reader.lineProgress, 0)
        XCTAssertNotNil(reader.errorMessage)
        reader.makeSynthesizer = { (OneShotSynthesizer(), nil) }
        reader.pauseOrResume()
        try await waitUntil { reader.phase == .playing }
        XCTAssertNil(reader.errorMessage)
    }

    func testDocumentLateSynthesisCannotAppendOrEndReplacementAfterFailure() async throws {
        let player = RecordingAudioPlayer()
        let reader = ReadAloudDocumentReader(player: player)
        reader.coordinator = nil
        defer { reader.stop() }
        let synth = LateLineSynthesizer()
        reader.makeSynthesizer = { (synth, nil) }
        reader.read("This first sentence is long enough to remain a separate line. This second sentence stays in flight during retry.")
        for _ in 0..<100 where !(await synth.isWaiting) { try await Task.sleep(for: .milliseconds(10)) }
        let wasWaiting = await synth.isWaiting
        XCTAssertTrue(wasWaiting)
        XCTAssertEqual(reader.phase, .playing)
        player.onPlaybackFailure?(ReadAloudPlaybackFailure.outputChanged)
        reader.makeSynthesizer = { (OneShotSynthesizer(), nil) }
        reader.start(from: 0)
        try await waitUntil { reader.phase == .playing }
        let appends = player.appendStreamingCalls
        let ends = player.endStreamingCalls
        try await Task.sleep(for: .milliseconds(180))
        XCTAssertEqual(player.appendStreamingCalls, appends)
        XCTAssertEqual(player.endStreamingCalls, ends)
        XCTAssertEqual(reader.phase, .playing)
        XCTAssertNil(reader.errorMessage)
    }

    func testDocumentFailureDuringAnchorWaitCannotReenterPlaying() async throws {
        let player = RecordingAudioPlayer()
        player.anchorDelay = .seconds(30)
        let reader = ReadAloudDocumentReader(player: player)
        reader.coordinator = nil
        defer { reader.stop() }
        reader.makeSynthesizer = { (OneShotSynthesizer(), nil) }
        reader.read("A complete sentence that is waiting for the audio clock to begin.")
        try await waitUntil { player.appendStreamingCalls == 1 }
        XCTAssertEqual(reader.phase, .preparing)
        player.onPlaybackFailure?(ReadAloudPlaybackFailure.outputChanged)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(reader.phase, .idle)
        XCTAssertNotNil(reader.errorMessage)
        XCTAssertEqual(player.endStreamingCalls, 0)
        XCTAssertTrue(reader.shouldShowControls)
        reader.stop()
        XCTAssertFalse(reader.shouldShowControls)
        XCTAssertNil(reader.errorMessage)
    }

    func testPauseCancelsProviderButKeepsQueuedAudioPausedWithoutFailure() async throws {
        let player = RecordingAudioPlayer()
        let stream = ControlledReadAloudStream()
        let reader = makeReader(player: player, streams: [stream])
        defer { reader.stop() }
        reader.toggleRead(.sample)
        try await waitUntil { player.beginStreamingRates.count == 1 }
        stream.yield()
        try await waitUntil { reader.isPlaying }
        reader.pauseOrResume()
        try await waitUntil { stream.cancellationCount == 1 }
        XCTAssertFalse(reader.isPlaying)
        XCTAssertNil(reader.lastErrorMessage)
        XCTAssertEqual(player.endStreamingCalls, 1)
        reader.pauseOrResume()
        XCTAssertTrue(reader.isPlaying)
    }

    private func makeReader(player: RecordingAudioPlayer, streams: [ControlledReadAloudStream]) -> ReadAloudController {
        let reader = ReadAloudController(player: player)
        reader.coordinator = nil
        reader.preflightForPlayback = { _ in (false, false) }
        var remaining = streams
        reader.makeStreamingSynthesizer = { remaining.removeFirst() }
        reader.makeFallbackAttempts = { XCTFail("Device failure must not start fallback synthesis"); return [] }
        return reader
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<100 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition())
    }


}

private final class ControlledReadAloudStream: StreamingSpeechSynthesizer, @unchecked Sendable {
    private let lock = NSLock()
    private var cancellations = 0
    private let value: AsyncThrowingStream<SynthesizedSpeech, Error>
    private let continuation: AsyncThrowingStream<SynthesizedSpeech, Error>.Continuation
    var cancellationCount: Int { lock.withLock { cancellations } }

    init() {
        (value, continuation) = AsyncThrowingStream.makeStream()
        continuation.onTermination = { [weak self] reason in
            if case .cancelled = reason { self?.lock.withLock { self?.cancellations += 1 } }
        }
    }
    func stream(_ text: String, speed: Double) -> AsyncThrowingStream<SynthesizedSpeech, Error> { value }
    func yield() { continuation.yield(SynthesizedSpeech(samples: [0, 0.2, -0.2, 0], sampleRate: 24_000)) }
    func finish() { continuation.finish() }
}

private actor CancellationObservingLineSynthesizer: SpeechSynthesizer {
    private var calls = 0
    private(set) var isWaiting = false
    private(set) var wasCancelled = false
    func synthesize(_ text: String, speed: Double) async throws -> SynthesizedSpeech {
        calls += 1
        if calls > 1 {
            isWaiting = true
            do { try await Task.sleep(for: .seconds(30)) }
            catch { wasCancelled = Task.isCancelled; throw error }
        }
        return SynthesizedSpeech(samples: [0, 0.2, -0.2, 0], sampleRate: 24_000)
    }
}

private actor LateLineSynthesizer: SpeechSynthesizer {
    private var calls = 0
    private(set) var isWaiting = false
    func synthesize(_ text: String, speed: Double) async throws -> SynthesizedSpeech {
        calls += 1
        if calls > 1 {
            isWaiting = true
            try? await Task.sleep(for: .milliseconds(120))
        }
        return SynthesizedSpeech(samples: [0, 0.2, -0.2, 0], sampleRate: 24_000)
    }
}
