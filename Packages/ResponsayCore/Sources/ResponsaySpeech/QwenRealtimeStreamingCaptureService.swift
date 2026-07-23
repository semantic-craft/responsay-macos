#if os(macOS)
import AVFoundation
import Foundation
import OSLog
import ResponsayCore

/// The first **live** streaming capture service (真·边说边推): while the hotkey is held it
/// taps the mic and pushes 16-bit PCM frames to the pinned Qwen3-ASR realtime snapshot over the
/// OmniRealtime WebSocket, surfacing `text+stash` partials to the capsule; on `stop()`
/// (Fn released) it `commit`s the turn and returns the `completed` transcript — the整段
/// source of truth for skills + insertion. Input streams; output stays whole-segment, so
/// the skill pipeline is untouched (Plan B).
///
/// HITL boundary: the mic tap, the socket drive, and the send/receive concurrency can only
/// be verified on a real Mac (mic + network). The pieces around it are unit-tested:
/// `QwenRealtimeASRProtocol` (codec), `QwenRealtimeASRClient` (fold), `QwenRealtimePCM`
/// (sample conversion).
@MainActor
public final class QwenRealtimeStreamingCaptureService: SpeechCaptureService {
    private let log = Logger(subsystem: AppBrand.loggerSubsystem, category: "qwen-realtime-capture")
    private let endpoint: QwenRealtimeEndpoint
    private let apiKeyProvider: @Sendable () -> String
    private let session: URLSession
    private let requireMicPermission: () throws -> Void

    private var recorder: AVCaptureAudioRecorder?
    private var socket: URLSessionWebSocketTask?
    private var client: QwenRealtimeASRClient?
    private var senderTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var audioContinuation: AsyncStream<Data>.Continuation?
    private var levelContinuation: AsyncStream<Float>.Continuation?
    private var partialContinuation: AsyncStream<String>.Continuation?
    private var finalStream: AsyncStream<Result<String, Error>>?
    private var finalContinuation: AsyncStream<Result<String, Error>>.Continuation?
    private var captureProfile: SpeechCaptureProfile = .dictation

    /// How long `stop()` waits for the terminal transcript after `commit` before giving up
    /// (returns "" rather than wedging the input method).
    private let finalTimeoutNanos: UInt64 = 8_000_000_000

    public private(set) var levels: AsyncStream<Float> = AsyncStream { _ in }
    public private(set) var partialTranscripts: AsyncStream<String> = AsyncStream { $0.finish() }

    public init(
        endpoint: QwenRealtimeEndpoint = QwenRealtimeEndpoint(),
        apiKeyProvider: @escaping @Sendable () -> String,
        session: URLSession = .shared,
        requireMicPermission: @escaping () throws -> Void
    ) {
        self.endpoint = endpoint
        self.apiKeyProvider = apiKeyProvider
        self.session = session
        self.requireMicPermission = requireMicPermission
    }

    public func start(locale: CaptureLocale) throws {
        try requireMicPermission()
        let key = apiKeyProvider()
        guard !key.isEmpty else {
            throw CoachAPIError.message("未配置千问 API Key。请在设置中配置。")
        }

        var request = URLRequest(url: endpoint.url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let socket = session.webSocketTask(with: request)
        socket.resume()
        let client = QwenRealtimeASRClient(transport: socket)
        self.socket = socket
        self.client = client

        let (partialStream, partialCont) = AsyncStream.makeStream(of: String.self)
        partialTranscripts = partialStream
        partialContinuation = partialCont
        let (levelStream, levelCont) = AsyncStream.makeStream(of: Float.self)
        levels = levelStream
        levelContinuation = levelCont
        let (audioStream, audioCont) = AsyncStream.makeStream(of: Data.self)
        audioContinuation = audioCont
        let (finalStream, finalCont) = AsyncStream.makeStream(of: Result<String, Error>.self)
        self.finalStream = finalStream
        finalContinuation = finalCont

        let language = locale == .chinese ? "zh" : "en"
        // Sender: session.update first, then drain audio frames IN ORDER (AsyncStream keeps
        // yield order; a single consumer preserves it — Tasks-per-buffer would reorder).
        senderTask = Task.detached {
            try? await client.sendSessionUpdate(language: language, sampleRate: 16_000, format: "pcm")
            for await pcm in audioStream {
                try? await client.sendAudio(pcm)
            }
        }
        // Receiver: fold events → partial (capsule) / final (source of truth).
        receiveTask = Task.detached {
            do {
                while true {
                    let event = try await client.receive()
                    guard let update = await client.handleEvent(event) else { continue }
                    switch update {
                    case .partial(let preview):
                        partialCont.yield(preview)
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
        log.info("qwen realtime capture started (\(locale.rawValue, privacy: .public))")
    }

    public func stop() async throws -> String {
        recorder?.stop()
        recorder = nil
        levelContinuation?.finish()
        levelContinuation = nil
        audioContinuation?.finish()   // ends the sender loop once buffered audio drains
        audioContinuation = nil
        await senderTask?.value        // all audio flushed before we end the turn
        senderTask = nil
        try? await client?.commit()    // Fn released → close the turn → server emits `completed`
        let text = await awaitFinal()
        cleanup()
        log.info("qwen realtime transcript length \(text.count, privacy: .public)")
        return text
    }

    public func setCaptureProfile(_ profile: SpeechCaptureProfile) {
        captureProfile = profile
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
        partialContinuation?.finish()
        partialContinuation = nil
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

extension QwenRealtimeStreamingCaptureService: SpeechCaptureProfileConfigurable {}
extension QwenRealtimeStreamingCaptureService: SpeechPartialTranscriptProviding {}

extension QwenRealtimeStreamingCaptureService {
    /// 真·边说边推: frame-by-frame live partials + profile-aware. Cloud realtime keeps `needsEchoFilter`
    /// conservatively (unchanged from today; it streams frames rather than injecting a text list).
    public var captureCapability: SpeechCaptureCapability {
        .init(partialStyle: .realtimeFrameByFrame, profileAware: true, needsEchoFilter: true)
    }
}
#endif
