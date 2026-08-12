#if os(macOS)
import AVFoundation
import Foundation
import OSLog
import ResponsayCore

/// 阿里云百炼 实时语音识别 (run-task protocol) as a live capture service: while the hotkey is held
/// it taps the mic and streams 16 kHz mono PCM frames to `qwen-audio-3.0-asr-flash-streaming`; on
/// release it sends `finish-task` and returns the joined 整段 transcript.
///
/// Deliberately **final-only** (`partialStyle: .none`): the server does emit per-sentence
/// intermediate results, but a live word-by-word capsule preview is not wanted — the insertion path
/// has always been whole-segment, and the flicker causes more trouble than it solves. Streaming is
/// here for latency: the audio is already recognised by the time the hotkey comes up, so
/// release→text is far shorter than uploading a whole clip afterwards.
///
/// HITL boundary: the mic tap and production socket can only be verified on a real Mac
/// (mic + network). Run-task sequencing, folding, replay, and reconnect are verified through
/// `QwenRunTaskSession`; sample conversion is verified through `QwenRealtimePCM`.
@MainActor
public final class QwenRunTaskStreamingCaptureService: SpeechCaptureService {
    private let log = Logger(subsystem: AppBrand.loggerSubsystem, category: "qwen-runtask-capture")
    private let configProvider: () -> QwenRunTaskCaptureConfig
    private let prepareConfig: @Sendable (QwenRunTaskCaptureConfig) async throws -> QwenRunTaskCaptureConfig
    private let contextRecorder: @MainActor @Sendable (String, String?) -> [String]
    private let runTask: any QwenRunTaskTranscribing
    private let audioRecorder: () -> any SpeechAudioRecording
    private let requireMicPermission: () throws -> Void

    private var recorder: (any SpeechAudioRecording)?
    private var audioContinuation: AsyncStream<Data>.Continuation?
    private var transcriptionTask: Task<String, Error>?
    private var levelContinuation: AsyncStream<Float>.Continuation?
    private var progress: CaptureProgress?

    /// Running tally for one capture: PCM bytes recorded (sizes `stop()`'s final wait) and the
    /// final sentences observed so far. The session already dedups the sentence callback across
    /// its reconnect replays, so if it ultimately fails, joining these salvages everything
    /// recognised up to the failure instead of dropping the whole recording.
    private final class CaptureProgress: @unchecked Sendable {
        private let lock = NSLock()
        private var segments: [String] = []
        private var bytes = 0

        func addBytes(_ count: Int) {
            lock.lock()
            bytes += count
            lock.unlock()
        }

        func appendFinal(_ text: String) {
            lock.lock()
            segments.append(text)
            lock.unlock()
        }

        var audioBytes: Int {
            lock.lock()
            defer { lock.unlock() }
            return bytes
        }

        var salvagedTranscript: String {
            lock.lock()
            defer { lock.unlock() }
            return TranscriptJoiner.mergeSegments(segments)
        }
    }

    public private(set) var levels: AsyncStream<Float> = AsyncStream { _ in }
    /// Final-only by design — see the type doc. Consumers' partial loops simply end.
    public private(set) var partialTranscripts: AsyncStream<String> = AsyncStream { $0.finish() }

    public init(
        configProvider: @escaping () -> QwenRunTaskCaptureConfig,
        prepareConfig: @escaping @Sendable (QwenRunTaskCaptureConfig) async throws -> QwenRunTaskCaptureConfig = { $0 },
        runTask: (any QwenRunTaskTranscribing)? = nil,
        audioRecorder: @escaping () -> any SpeechAudioRecording = { AVCaptureAudioRecorder() },
        contextRecorder: @escaping @MainActor @Sendable (String, String?) -> [String] = { _, _ in [] },
        requireMicPermission: @escaping () throws -> Void
    ) {
        self.configProvider = configProvider
        self.prepareConfig = prepareConfig
        self.runTask = runTask ?? QwenRunTaskSession()
        self.audioRecorder = audioRecorder
        self.contextRecorder = contextRecorder
        self.requireMicPermission = requireMicPermission
    }

    public func start(locale: CaptureLocale) throws {
        try requireMicPermission()
        var baseConfig = configProvider()
        guard !baseConfig.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CoachAPIError.message("未配置阿里云百炼 API Key。请在设置中配置。")
        }
        baseConfig.captureLocale = locale

        let (levelStream, levelCont) = AsyncStream.makeStream(of: Float.self)
        levels = levelStream
        levelContinuation = levelCont
        let (audio, audioContinuation) = AsyncStream.makeStream(of: Data.self)
        self.audioContinuation = audioContinuation

        let contextScope = baseConfig.contextScope
        let contextRecorder = self.contextRecorder
        let prepareConfig = self.prepareConfig
        let runTask = self.runTask
        let log = self.log
        let progress = CaptureProgress()
        self.progress = progress
        transcriptionTask = Task.detached {
            let config = try await prepareConfig(baseConfig)
            try Task.checkCancellation()
            return try await runTask.transcribe(
                config: config,
                audio: audio,
                onFinalSentence: { text in
                    progress.appendFinal(text)
                    return await contextRecorder(text, contextScope)
                },
                onTaskStarted: { metric in
                    let milliseconds = Double(metric.runTaskToStartedNanos) / 1_000_000
                    log.info("qwen task started (reused connection \(metric.reusedConnection, privacy: .public), run-task latency \(milliseconds, format: .fixed(precision: 1), privacy: .public) ms)")
                })
        }

        let recorder = audioRecorder()
        self.recorder = recorder
        do {
            try recorder.start(preferredUID: AudioInputDeviceSelector.preferredUID) { @Sendable buffer in
                guard let channel = buffer.floatChannelData, buffer.frameLength > 0 else { return }
                let count = Int(buffer.frameLength)
                let floats = Array(UnsafeBufferPointer(start: channel[0], count: count))
                var sumOfSquares: Float = 0
                for value in floats { sumOfSquares += value * value }
                levelCont.yield(min(1, (sumOfSquares / Float(count)).squareRoot() * 8))
                let pcm = QwenRealtimePCM.int16LE(from: floats)
                progress.addBytes(pcm.count)
                audioContinuation.yield(pcm)
            }
        } catch {
            audioContinuation.finish()
            transcriptionTask?.cancel()
            cleanupTaskState()
            throw error
        }
        log.info("qwen run-task capture started (\(locale.rawValue, privacy: .public), model \(baseConfig.model, privacy: .public), dedicated host \(baseConfig.endpoint.usesDedicatedHost, privacy: .public))")
    }

    public func stop() async throws -> String {
        recorder?.stop()
        recorder = nil
        levelContinuation?.finish()
        levelContinuation = nil
        audioContinuation?.finish()
        let progress = self.progress
        defer { cleanupTaskState() }
        do {
            let text = try await awaitFinal(
                timeoutNanos: Self.stopWaitNanos(audioBytes: progress?.audioBytes ?? 0))
            log.info("qwen run-task transcript length \(text.count, privacy: .public)")
            return text
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // The session failed even after its own retries. Salvage the finals it already
            // recognised — a long dictation must degrade to "missing the tail", never to nothing.
            let salvaged = progress?.salvagedTranscript ?? ""
            let seconds = (progress?.audioBytes ?? 0) / 32_000
            log.error("qwen run-task session failed after \(seconds, privacy: .public)s of audio, salvaged \(salvaged.count, privacy: .public) chars: \(error.localizedDescription, privacy: .public)")
            guard !salvaged.isEmpty else { throw error }
            return salvaged
        }
    }

    /// How long `stop()` waits for the terminal transcript: scales with the recording length so a
    /// reconnect replay of a multi-minute capture can still finish, capped so the input method can
    /// never wedge. Kept above the session's own final wait (90 s cap) so the session times out
    /// first and its error reaches the salvage path before this deadline cancels it.
    nonisolated static func stopWaitNanos(audioBytes: Int) -> UInt64 {
        let scaled = 12_000_000_000 + UInt64(max(0, audioBytes)) * 15_625
        return min(scaled, 120_000_000_000)
    }

    /// Await the terminal transcript while preserving timeout, task-failure and caller-cancellation
    /// outcomes for the production router.
    private func awaitFinal(timeoutNanos: UInt64) async throws -> String {
        guard let transcriptionTask else { return "" }
        let timeout = timeoutNanos
        return try await withTaskCancellationHandler {
            do {
                return try await withThrowingTaskGroup(of: String.self) { group in
                    group.addTask {
                        try await transcriptionTask.value
                    }
                    group.addTask {
                        try await Task.sleep(nanoseconds: timeout)
                        transcriptionTask.cancel()
                        throw QwenRunTaskSessionError.taskResponseTimedOut
                    }
                    defer { group.cancelAll() }
                    guard let first = try await group.next() else {
                        throw QwenRunTaskSessionError.taskEndedWithoutFinal
                    }
                    return first
                }
            } catch {
                transcriptionTask.cancel()
                throw error
            }
        } onCancel: {
            transcriptionTask.cancel()
        }
    }

    private func cleanupTaskState() {
        transcriptionTask = nil
        audioContinuation = nil
        progress = nil
    }
}

extension QwenRunTaskStreamingCaptureService: SpeechPartialTranscriptProviding {}

extension QwenRunTaskStreamingCaptureService {
    /// Final-only: streaming buys latency here, not a live preview (see the type doc).
    /// `needsEchoFilter` stays on, matching every other cloud engine — the 词典 does reach the
    /// request (as structured 即时热词), so the conservative guard is kept.
    public var captureCapability: SpeechCaptureCapability {
        .init(partialStyle: .none, needsEchoFilter: true)
    }
}
#endif
