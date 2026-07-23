import Foundation

/// Shared TTS audio constants (issue 187/195) — the single source for values that
/// would otherwise be duplicated across cloud adapters, catalogs, and playback.
public enum TTSAudio {
    /// PCM sample rate the surveyed cloud TTS providers emit (Qwen/Gemini headerless
    /// PCM, Kokoro/most providers). On-device Kokoro reports its own rate from the
    /// engine; this is the assumed rate where the wire format carries none.
    public static let defaultSampleRate = 24_000
}

/// The result of synthesizing one piece of text: raw audio plus, where the
/// provider supplies it, word-level timing (issue 201 / spec §Architecture).
///
/// On-device Kokoro returns audio only (`providerTiming == nil`) — the ONNX model
/// exposes no native word alignment, so timing is approximated downstream by the
/// `WordTimingAligner` proportional path. Cloud providers that return word/char
/// timestamps populate `providerTiming` for exact highlight.
public struct SynthesizedSpeech: Sendable, Equatable {
    /// Mono PCM samples normalized to [-1, 1].
    public let samples: [Float]
    /// Sample rate of `samples` in Hz (Kokoro = 24_000).
    public let sampleRate: Int
    /// Provider-supplied word timing, or `nil` when only audio is available.
    public let providerTiming: [TimedWord]?

    public init(samples: [Float], sampleRate: Int, providerTiming: [TimedWord]? = nil) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.providerTiming = providerTiming
    }

    /// Playback duration in seconds. `0` when the sample rate is unusable, so
    /// callers never divide by zero.
    public var duration: TimeInterval {
        sampleRate > 0 ? Double(samples.count) / Double(sampleRate) : 0
    }
}

/// Failures a synthesizer can surface — semantic cases so call sites can branch and the
/// UI/diagnostics layer maps presentation text (issue 201; R6 restructure issue 199).
/// The core type carries no localized UI strings; see `userMessage`.
public enum TTSError: Error, Sendable, Equatable {
    /// The local voice model isn't downloaded → UI directs the user to 本地模型.
    case modelNotInstalled
    /// Nothing to speak.
    case emptyText
    /// No BYOK key configured for `provider` (cloud engines).
    case missingAPIKey(provider: String)
    /// Provider returned a non-2xx HTTP status.
    case http(status: Int)
    /// Provider accepted the request but returned no audio.
    case providerReturnedNoAudio(provider: String)
    /// Transport/connection failure; payload is the underlying description.
    case network(String)
    /// Generic escape hatch for engine failures that don't fit a case above.
    case synthesisFailed(String)

    /// Human-facing message — presentation layer, kept out of the cases themselves so
    /// the core type stays free of UI strings (and can be re-localized later).
    public var userMessage: String {
        switch self {
        case .modelNotInstalled:
            "请到「设置 › 本地模型」下载语音模型后再使用。"
        case .emptyText:
            "没有可朗读的文本。"
        case .missingAPIKey(let provider):
            "\(provider) 未配置 API Key，请在「设置 › 语音合成」填写。"
        case .http(let status):
            "语音服务返回错误（HTTP \(status)），请检查 Key 或稍后重试。"
        case .providerReturnedNoAudio(let provider):
            "\(provider) 未返回音频，请重试或换一个引擎。"
        case .network(let detail):
            "网络错误：\(detail)"
        case .synthesisFailed(let detail):
            detail
        }
    }
}

/// The single abstraction every TTS engine implements — on-device sherpa (v1) and
/// cloud providers (later) — so the read-aloud pipeline never knows which engine it
/// talks to (issue 201). Pure boundary: no engine, audio, or network types here.
///
/// `speed` is the speaking rate (issue 198): 1.0 = natural, applied at synthesis so the
/// produced audio duration already reflects it and the proportional timeline stays in
/// sync. Engines clamp to a sane band.
public protocol SpeechSynthesizer: Sendable {
    func synthesize(_ text: String, speed: Double) async throws -> SynthesizedSpeech
}

public extension SpeechSynthesizer {
    /// Convenience: synthesize at the natural 1.0× rate.
    func synthesize(_ text: String) async throws -> SynthesizedSpeech {
        try await synthesize(text, speed: 1.0)
    }

    /// Speaking-rate band shared by engines (issue 198).
    static func clampSpeed(_ speed: Double) -> Double { min(2.0, max(0.5, speed)) }
}
