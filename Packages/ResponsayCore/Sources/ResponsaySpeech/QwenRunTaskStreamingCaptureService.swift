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

    /// How long `stop()` waits for `task-finished` after `finish-task` before giving up.
    private let finalTimeoutNanos: UInt64 = 12_000_000_000

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
        transcriptionTask = Task.detached {
            let config = try await prepareConfig(baseConfig)
            try Task.checkCancellation()
            return try await runTask.transcribe(
                config: config,
                audio: audio,
                onFinalSentence: { text in await contextRecorder(text, contextScope) },
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
                audioContinuation.yield(QwenRealtimePCM.int16LE(from: floats))
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
        defer { cleanupTaskState() }
        let text = try await awaitFinal()
        log.info("qwen run-task transcript length \(text.count, privacy: .public)")
        return text
    }

    /// Await the terminal transcript while preserving timeout, task-failure and caller-cancellation
    /// outcomes for the production router.
    private func awaitFinal() async throws -> String {
        guard let transcriptionTask else { return "" }
        let timeout = finalTimeoutNanos
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
