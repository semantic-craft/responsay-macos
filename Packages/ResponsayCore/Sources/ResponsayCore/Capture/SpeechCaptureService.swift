import Foundation

public enum CaptureLocale: String, Sendable, CaseIterable {
    case automatic = "auto"
    case english = "en-US"
    case chinese = "zh-CN"
    /// Chinese-led bilingual recognition. Providers without multi-hint support fall back to
    /// Chinese, while Qwen-Audio 3.0 receives both `zh` and `en`.
    case mixed = "zh-Hans"
}

public enum SpeechCaptureProfile: String, Sendable, Equatable {
    /// Default dictation profile: provider-side punctuation/normalization is allowed.
    case dictation
    /// Coach/practice profile: keep the utterance as close to what was spoken as possible.
    case faithful
}

/// 麦克风 → 文本(+ 录音时的实时电平 0...1,给波形用)。start 开始拾音,stop 结束并返回最终转写。
@MainActor
public protocol SpeechCaptureService: AnyObject {
    func start(locale: CaptureLocale) throws
    func stop() async throws -> String
    func cancel() async
    /// 录音期间持续产出 RMS 电平(0...1)。非录音期间不产出。
    var levels: AsyncStream<Float> { get }
    var captureFailures: AsyncStream<String> { get }
    /// What this engine can do — partials style, profile-awareness, echo risk — declared explicitly
    /// so the router dispatches per capability instead of `as?`-casting optional protocols.
    var captureCapability: SpeechCaptureCapability { get }
}

public extension SpeechCaptureService {
    func cancel() async { _ = try? await stop() }
    var captureFailures: AsyncStream<String> { AsyncStream { $0.finish() } }
    /// On-device / final-only default: no partials, profile-agnostic, cannot echo a biasing list.
    /// Cloud and realtime adapters override.
    var captureCapability: SpeechCaptureCapability { .init() }
}

@MainActor
public protocol SpeechCaptureProfileConfigurable: AnyObject {
    func setCaptureProfile(_ profile: SpeechCaptureProfile)
}

@MainActor
public protocol SpeechPartialTranscriptProviding: AnyObject {
    /// Live ASR preview while recording. Services that only return a final
    /// transcript can omit this protocol.
    var partialTranscripts: AsyncStream<String> { get }
}

@MainActor
public protocol SpeechActivityProviding: AnyObject {
    /// Server-VAD speech activity while recording: `true` on speech onset,
    /// `false` when the server detects end of speech. Drives a "listening"
    /// indicator. Services without server VAD can omit this protocol.
    var speechActivity: AsyncStream<Bool> { get }
}

/// Main-actor ownership of one recording's terminal failure. Old callbacks cannot fail a new turn.
@MainActor
public final class SpeechCaptureFailureState {
    public private(set) var stream: AsyncStream<String> = AsyncStream { $0.finish() }
    private var continuation: AsyncStream<String>.Continuation?
    private var generation: UUID?
    private var message: String?

    public init() {}

    public func begin() -> UUID {
        continuation?.finish()
        let pair = AsyncStream.makeStream(of: String.self)
        stream = pair.stream
        continuation = pair.continuation
        message = nil
        let id = UUID()
        generation = id
        return id
    }

    public func fail(_ message: String, generation: UUID, cleanup: () -> Void) {
        guard self.generation == generation else { return }
        self.generation = nil
        self.message = message
        cleanup()
        continuation?.yield(message)
        continuation?.finish()
        continuation = nil
    }

    public func end() throws {
        generation = nil
        continuation?.finish()
        continuation = nil
        if let message { throw CoachAPIError.message(message) }
    }
}
