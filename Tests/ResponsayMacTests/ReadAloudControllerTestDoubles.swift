@testable import ResponsayMac
import ResponsayCore

actor RecordingSynthesizer: SpeechSynthesizer {
    private var calls: [String] = []
    var recordedCalls: [String] { calls }

    func synthesize(_ text: String, speed: Double) async throws -> SynthesizedSpeech {
        calls.append(text)
        return SynthesizedSpeech(samples: [0, 0.1, 0, -0.1], sampleRate: 24_000)
    }
}

actor FailingSynthesizer: SpeechSynthesizer {
    private let error: TTSError
    private var calls: [String] = []

    init(_ error: TTSError) { self.error = error }
    var recordedCalls: [String] { calls }

    func synthesize(_ text: String, speed: Double) async throws -> SynthesizedSpeech {
        calls.append(text)
        throw error
    }
}

actor FixedSynthesizer: SpeechSynthesizer {
    private let samples: [Float]
    private var calls: [String] = []

    init(samples: [Float]) { self.samples = samples }
    var recordedCalls: [String] { calls }

    func synthesize(_ text: String, speed: Double) async throws -> SynthesizedSpeech {
        calls.append(text)
        return SynthesizedSpeech(samples: samples, sampleRate: 24_000)
    }
}

actor SlowSynthesizer: SpeechSynthesizer {
    func synthesize(_ text: String, speed: Double) async throws -> SynthesizedSpeech {
        try await Task.sleep(for: .milliseconds(200))
        return SynthesizedSpeech(samples: [0, 0.1, 0, -0.1], sampleRate: 24_000)
    }
}

actor SlowRecordingSynthesizer: SpeechSynthesizer {
    private var calls: [String] = []
    private var started = false

    var recordedCalls: [String] { calls }
    var didStart: Bool { started }

    func synthesize(_ text: String, speed: Double) async throws -> SynthesizedSpeech {
        started = true
        calls.append(text)
        try await Task.sleep(for: .milliseconds(200))
        return SynthesizedSpeech(samples: [0, 0.2, -0.2, 0], sampleRate: 24_000)
    }
}

actor DelayedSynthesizer: SpeechSynthesizer {
    let delayMs: Int

    init(delayMs: Int) { self.delayMs = delayMs }

    func synthesize(_ text: String, speed: Double) async throws -> SynthesizedSpeech {
        try? await Task.sleep(for: .milliseconds(delayMs))
        return SynthesizedSpeech(samples: [0, 0.2, -0.2, 0], sampleRate: 24_000)
    }
}

actor OneShotSynthesizer: SpeechSynthesizer {
    func synthesize(_ text: String, speed: Double) async throws -> SynthesizedSpeech {
        SynthesizedSpeech(samples: [0, 0.2, -0.2, 0], sampleRate: 24_000)
    }
}

/// Scripted streaming synthesizer covering the P1-07 fault matrix (issue 486). Keeps
/// the `FailingStreamingSynthesizer` name (some scenarios are non-failing — latency and
/// normal completion exercise the success path).
struct FailingStreamingSynthesizer: StreamingSpeechSynthesizer {
    enum Failure: Sendable {
        case beforeFirstChunk    // throw before any chunk (UT-06)
        case afterFirstChunk     // one chunk, then throw mid-playback (UT-07)
        case thirdChunkThrow     // two chunks, then throw on the third
        case firstChunkLatency   // delayed first chunk, then complete cleanly
        case closeWithoutAudio   // finish cleanly with zero chunks
        case normalComplete      // a couple of chunks, then finish cleanly
    }

    let failure: Failure
    private static let chunk = SynthesizedSpeech(samples: [0, 0.2, -0.2, 0], sampleRate: 24_000)

    func stream(_ text: String, speed: Double) -> AsyncThrowingStream<SynthesizedSpeech, Error> {
        let chunk = Self.chunk
        let failure = self.failure
        return AsyncThrowingStream { continuation in
            switch failure {
            case .beforeFirstChunk:
                continuation.finish(throwing: TTSError.synthesisFailed("stream failed"))
            case .afterFirstChunk:
                continuation.yield(chunk)
                continuation.finish(throwing: TTSError.synthesisFailed("stream failed"))
            case .thirdChunkThrow:
                continuation.yield(chunk)
                continuation.yield(chunk)
                continuation.finish(throwing: TTSError.synthesisFailed("stream failed"))
            case .firstChunkLatency:
                Task {
                    try? await Task.sleep(for: .milliseconds(120))
                    continuation.yield(chunk)
                    continuation.finish()
                }
            case .closeWithoutAudio:
                continuation.finish()
            case .normalComplete:
                continuation.yield(chunk)
                continuation.yield(chunk)
                continuation.finish()
            }
        }
    }
}

@MainActor
final class RecordingAudioPlayer: ReadAloudAudioPlaying {
    var elapsed: TimeInterval = 0
    var isFinished = false
    private(set) var playCalls: [ComposedReadAloud] = []
    private(set) var stopCalls = 0
    private(set) var appendStreamingCalls = 0
    private(set) var beginStreamingRates: [Double] = []
    private(set) var endStreamingCalls = 0

    func play(_ composed: ComposedReadAloud) throws {
        playCalls.append(composed)
        elapsed = 0
        isFinished = false
    }

    func waitForPlaybackAnchor(timeout: TimeInterval) async -> Bool { true }
    func playFileEmergency(_ composed: ComposedReadAloud) -> Bool { false }
    func beginStreaming(sampleRate: Double) throws {
        beginStreamingRates.append(sampleRate)
    }
    func appendStreaming(_ speech: SynthesizedSpeech) -> TimeInterval {
        appendStreamingCalls += 1
        return speech.duration
    }
    func endStreaming() {
        endStreamingCalls += 1
    }
    func pause() {}
    func resume() {}
    func stop() {
        stopCalls += 1
        elapsed = 0
        isFinished = false
    }
}

/// Engine never anchors; file emergency succeeds and immediately reports finished, so the
/// 复读 loop trips `reset()` — lets a test observe whether the loop replays via emergency
/// or falls back through the broken engine.
@MainActor
final class EmergencyLoopingAudioPlayer: ReadAloudAudioPlaying {
    var elapsed: TimeInterval = 0
    var isFinished = false
    private(set) var playCalls = 0
    private(set) var emergencyCalls = 0

    func play(_ composed: ComposedReadAloud) throws { playCalls += 1 }   // engine: never anchors
    func waitForPlaybackAnchor(timeout: TimeInterval) async -> Bool { false }
    func playFileEmergency(_ composed: ComposedReadAloud) -> Bool {
        emergencyCalls += 1
        isFinished = true   // emergency "completes" so the loop tries to reset
        return true
    }
    func beginStreaming(sampleRate: Double) throws {}
    func appendStreaming(_ speech: SynthesizedSpeech) -> TimeInterval { 0 }
    func endStreaming() {}
    func pause() {}
    func resume() {}
    func stop() {}
}

@MainActor
final class NeverAnchoredAudioPlayer: ReadAloudAudioPlaying {
    var elapsed: TimeInterval = 0
    var isFinished = false
    /// 484: whether the file-level emergency path "starts sound".
    var emergencyShouldSucceed = false
    private(set) var playCalls = 0
    private(set) var emergencyCalls = 0

    func play(_ composed: ComposedReadAloud) throws { playCalls += 1 }
    func waitForPlaybackAnchor(timeout: TimeInterval) async -> Bool { false }
    func playFileEmergency(_ composed: ComposedReadAloud) -> Bool {
        emergencyCalls += 1
        return emergencyShouldSucceed
    }
    func beginStreaming(sampleRate: Double) throws {}
    func appendStreaming(_ speech: SynthesizedSpeech) -> TimeInterval { 0 }
    func endStreaming() {}
    func pause() {}
    func resume() {}
    func stop() {}
}
