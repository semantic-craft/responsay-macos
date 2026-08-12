import AVFoundation
import ResponsayCore
@testable import ResponsaySpeech

final class ASRCredentialStore: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    func read(_ account: String) -> String? {
        lock.withLock { values[account] }
    }

    func write(_ value: String, account: String) {
        lock.withLock { values[account] = value }
    }
}

/// Local adapter for the two true external inputs in Qwen dictation: microphone audio and the
/// remote run-task exchange. The router and shipped capture adapter remain real; only hardware and
/// network are replaced.
final class LocalQwenDictationAdapter: @unchecked Sendable,
    SpeechAudioRecording, QwenRunTaskTranscribing
{
    enum Completion: Sendable {
        case transcript(String)
        case timeout
        case taskFailure(String)
        case waitForCancellation
    }

    private let lock = NSLock()
    private let completion: Completion
    private let finalSentences: [String]
    private var onBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?
    private var _started = false
    private var _stopped = false
    private var _waitingForCancellation = false
    private var _wasCancelled = false
    private var _config: QwenRunTaskCaptureConfig?
    private var _audio = [Data]()
    private var _callbackContext = [String]()

    init(
        completion: Completion = .transcript("推到代码厂里"),
        finalSentences: [String] = ["前一段原始转写"]
    ) {
        self.completion = completion
        self.finalSentences = finalSentences
    }

    var started: Bool { withLock { _started } }
    var stopped: Bool { withLock { _stopped } }
    var waitingForCancellation: Bool { withLock { _waitingForCancellation } }
    var wasCancelled: Bool { withLock { _wasCancelled } }
    var config: QwenRunTaskCaptureConfig? { withLock { _config } }
    var audio: [Data] { withLock { _audio } }
    var callbackContext: [String] { withLock { _callbackContext } }

    func start(
        preferredUID _: String,
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void
    ) throws {
        withLock {
            _started = true
            self.onBuffer = onBuffer
        }
    }

    func stop() {
        withLock {
            _stopped = true
            onBuffer = nil
        }
    }

    func deliver(_ samples: [Float]) {
        let format = AVCaptureAudioRecorder.deliveredFormat
        let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for (index, sample) in samples.enumerated() {
            buffer.floatChannelData![0][index] = sample
        }
        withLock { onBuffer }?(buffer)
    }

    func transcribe(
        config: QwenRunTaskCaptureConfig,
        audio: AsyncStream<Data>,
        onFinalSentence: @escaping @Sendable (String) async -> [String],
        onTaskStarted: @escaping @Sendable (QwenRunTaskStartMetric) async -> Void
    ) async throws -> String {
        withLock { _config = config }
        await onTaskStarted(.init(reusedConnection: false, runTaskToStartedNanos: 1_000_000))
        for await frame in audio {
            withLock { _audio.append(frame) }
        }
        for sentence in finalSentences {
            let updatedContext = await onFinalSentence(sentence)
            withLock { _callbackContext = updatedContext }
        }
        switch completion {
        case let .transcript(text):
            return text
        case .timeout:
            throw QwenRunTaskSessionError.taskResponseTimedOut
        case let .taskFailure(message):
            throw QwenRunTaskSessionError.taskFailed(message)
        case .waitForCancellation:
            withLock { _waitingForCancellation = true }
            do {
                try await Task.sleep(nanoseconds: 60_000_000_000)
                throw QwenRunTaskSessionError.taskResponseTimedOut
            } catch is CancellationError {
                withLock { _wasCancelled = true }
                throw CancellationError()
            }
        }
    }

    private func withLock<Value>(_ body: () -> Value) -> Value {
        lock.withLock(body)
    }
}

@MainActor
final class DeterministicDictationAdapter: SpeechCaptureService,
    SpeechPartialTranscriptProviding
{
    private let result: String
    private let level: Float
    private let partial: String?
    private let startError: Error?
    let captureCapability: SpeechCaptureCapability
    private var isCapturing = false
    private(set) var startedLocale: CaptureLocale?
    private(set) var didStop = false

    private(set) var levels: AsyncStream<Float> = AsyncStream { $0.finish() }
    private(set) var partialTranscripts: AsyncStream<String> = AsyncStream { $0.finish() }

    init(
        result: String,
        level: Float,
        partial: String?,
        capability: SpeechCaptureCapability,
        startError: Error? = nil
    ) {
        self.result = result
        self.level = level
        self.partial = partial
        self.captureCapability = capability
        self.startError = startError
    }

    func start(locale: CaptureLocale) throws {
        startedLocale = locale
        if let startError { throw startError }
        isCapturing = true
        levels = AsyncStream { continuation in
            continuation.yield(level)
            continuation.finish()
        }
        partialTranscripts = AsyncStream { continuation in
            if let partial { continuation.yield(partial) }
            continuation.finish()
        }
    }

    func stop() async throws -> String {
        guard isCapturing else { throw DeterministicDictationError.stopBeforeStart }
        isCapturing = false
        didStop = true
        return result
    }
}

enum DeterministicDictationError: Error, Equatable {
    case stopBeforeStart
    case missingLocalModel
}
