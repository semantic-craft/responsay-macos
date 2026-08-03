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
/// HITL boundary: the mic tap, the socket drive, and the send/receive concurrency can only be
/// verified on a real Mac (mic + network). The pieces around it are unit-tested:
/// `QwenRunTaskASRProtocol` (codec), `QwenRunTaskASRClient` (fold + start gate),
/// `QwenRealtimePCM` (sample conversion).
@MainActor
public final class QwenRunTaskStreamingCaptureService: SpeechCaptureService {
    private let log = Logger(subsystem: AppBrand.loggerSubsystem, category: "qwen-runtask-capture")
    private let configProvider: () -> QwenRunTaskCaptureConfig
    private let contextRecorder: @MainActor @Sendable (String, String?) -> [String]
    private let session: URLSession
    private let requireMicPermission: () throws -> Void

    private var recorder: AVCaptureAudioRecorder?
    private var socket: URLSessionWebSocketTask?
    private var client: QwenRunTaskASRClient?
    private var senderTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var audioContinuation: AsyncStream<Data>.Continuation?
    private var levelContinuation: AsyncStream<Float>.Continuation?
    private var finalStream: AsyncStream<Result<String, Error>>?
    private var finalContinuation: AsyncStream<Result<String, Error>>.Continuation?

    /// How long `stop()` waits for `task-finished` after `finish-task` before giving up
    /// (returns "" rather than wedging the input method).
    private let finalTimeoutNanos: UInt64 = 8_000_000_000

    public private(set) var levels: AsyncStream<Float> = AsyncStream { _ in }
    /// Final-only by design — see the type doc. Consumers' partial loops simply end.
    public private(set) var partialTranscripts: AsyncStream<String> = AsyncStream { $0.finish() }

    public init(
        configProvider: @escaping () -> QwenRunTaskCaptureConfig,
        session: URLSession = .shared,
        contextRecorder: @escaping @MainActor @Sendable (String, String?) -> [String] = { _, _ in [] },
        requireMicPermission: @escaping () throws -> Void
    ) {
        self.configProvider = configProvider
        self.session = session
        self.contextRecorder = contextRecorder
        self.requireMicPermission = requireMicPermission
    }

    public func start(locale: CaptureLocale) throws {
        try requireMicPermission()
        let config = configProvider()
        guard !config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CoachAPIError.message("未配置阿里云百炼 API Key。请在设置中配置。")
        }

        var request = URLRequest(url: config.endpoint.url)
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        // Optional per the docs, and redundant when the dedicated host already carries the space —
        // sent only on the generic host so a workspace-scoped key resolves there too.
        if !config.endpoint.usesDedicatedHost,
           let workspaceID = QwenRunTaskEndpoint.normalizedWorkspaceID(config.endpoint.workspaceID) {
            request.setValue(workspaceID, forHTTPHeaderField: "X-DashScope-WorkSpace")
        }
        let socket = session.webSocketTask(with: request)
        socket.resume()
        let client = QwenRunTaskASRClient(transport: socket)
        self.socket = socket
        self.client = client

        let (levelStream, levelCont) = AsyncStream.makeStream(of: Float.self)
        levels = levelStream
        levelContinuation = levelCont
        let (audioStream, audioCont) = AsyncStream.makeStream(of: Data.self)
        audioContinuation = audioCont
        let (finalStream, finalCont) = AsyncStream.makeStream(of: Result<String, Error>.self)
        self.finalStream = finalStream
        finalContinuation = finalCont

        let model = config.model
        let languageHints = QwenASRHotwords.languageHints(for: locale, model: model)
        let hotwords = config.hotwords
        let context = config.context
        let heartbeat = config.heartbeat
        let semanticPunctuationEnabled = config.semanticPunctuationEnabled
        let multiThresholdModeEnabled = config.multiThresholdModeEnabled
        // Sender: run-task, wait for task-started (audio before it is rejected), then drain frames
        // IN ORDER (AsyncStream keeps yield order; a single consumer preserves it).
        senderTask = Task.detached {
            do {
                try await client.sendRunTask(
                    model: model, sampleRate: 16_000, hotwords: hotwords,
                    languageHints: languageHints, context: context, heartbeat: heartbeat,
                    semanticPunctuationEnabled: semanticPunctuationEnabled,
                    multiThresholdModeEnabled: multiThresholdModeEnabled)
            } catch {
                return
            }
            // False = the task ended before it ever started (e.g. task-failed at handshake).
            // Draining the buffer keeps the producer from blocking; the frames just go nowhere.
            guard await client.awaitStarted() else {
                for await _ in audioStream {}
                return
            }
            for await pcm in audioStream {
                try? await client.sendAudio(pcm)
            }
        }
        // Receiver: fold events → the terminal 整段 transcript. Intermediate sentences update the
        // client's running transcript but are deliberately not surfaced as capsule partials.
        let contextScope = config.contextScope
        let contextRecorder = self.contextRecorder
        receiveTask = Task.detached {
            var recordedFinalSentenceIDs = Set<Int>()
            do {
                while true {
                    let event = try await client.receive()
                    if case let .sentence(id, text, true) = event,
                       recordedFinalSentenceIDs.insert(id).inserted,
                       !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        let updatedContext = await contextRecorder(text, contextScope)
                        try? await client.sendContinueTask(context: updatedContext)
                    }
                    guard let update = await client.handleEvent(event) else { continue }
                    switch update {
                    case .partial:
                        continue
                    case .final(let text):
                        finalCont.yield(.success(text)); finalCont.finish(); return
                    case .failed(let message):
                        finalCont.yield(.failure(CoachAPIError.message(message ?? "千问实时识别失败")))
                        finalCont.finish(); return
                    }
                }
            } catch {
                finalCont.yield(.failure(error)); finalCont.finish()
            }
        }

        let recorder = AVCaptureAudioRecorder()
        self.recorder = recorder
        try recorder.start(preferredUID: AudioInputDeviceSelector.preferredUID) { @Sendable buffer in
            guard let channel = buffer.floatChannelData, buffer.frameLength > 0 else { return }
            let count = Int(buffer.frameLength)
            let floats = Array(UnsafeBufferPointer(start: channel[0], count: count))
            var sumOfSquares: Float = 0
            for value in floats { sumOfSquares += value * value }
            levelCont.yield(min(1, (sumOfSquares / Float(count)).squareRoot() * 8))
            audioCont.yield(QwenRealtimePCM.int16LE(from: floats))
        }
        log.info("qwen run-task capture started (\(locale.rawValue, privacy: .public), model \(model, privacy: .public), dedicated host \(config.endpoint.usesDedicatedHost, privacy: .public))")
    }

    public func stop() async throws -> String {
        recorder?.stop()
        recorder = nil
        levelContinuation?.finish()
        levelContinuation = nil
        audioContinuation?.finish()   // ends the sender loop once buffered audio drains
        audioContinuation = nil
        await senderTask?.value        // all audio flushed before we end the task
        senderTask = nil
        try? await client?.finish()    // Fn released → server flushes the trailing sentence
        let text = await awaitFinal()
        cleanup()
        log.info("qwen run-task transcript length \(text.count, privacy: .public)")
        return text
    }

    /// Await the terminal transcript, or "" on timeout/failure (never hang the input method).
    private func awaitFinal() async -> String {
        guard let finalStream else { return "" }
        let timeout = finalTimeoutNanos
        return await withTaskGroup(of: String?.self) { group in
            group.addTask {
                for await result in finalStream { return (try? result.get()) ?? "" }
                return ""
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeout)
                return nil   // timeout sentinel
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return (first ?? nil) ?? ""
        }
    }

    private func cleanup() {
        finalContinuation?.finish()
        finalContinuation = nil
        finalStream = nil
        receiveTask?.cancel()
        receiveTask = nil
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        client = nil
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
