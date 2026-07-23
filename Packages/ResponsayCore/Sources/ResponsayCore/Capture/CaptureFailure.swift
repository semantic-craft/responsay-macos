import Foundation

/// Typed classification of a capture / ASR failure (issue 087 items 8.1 + 9).
/// Lets the capture flow show a clear message instead of a raw provider string
/// and decide whether an on-device fallback could still salvage the session.
public enum CaptureFailure: Equatable, Sendable {
    case noSpeech
    case audioTooLong
    case notAuthorized
    case network
    case timeout
    case provider(String)

    /// Best-effort classification from an arbitrary error. Pure / testable.
    public static func classify(_ error: Error) -> CaptureFailure {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return .timeout
            default:
                return .network
            }
        }
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return classify(message: message)
    }

    public static func classify(message: String) -> CaptureFailure {
        if message.contains("录音太长") || message.contains("10MB")
            || message.localizedCaseInsensitiveContains("too long") {
            return .audioTooLong
        }
        if message.contains("未授权") || message.contains("权限")
            || message.localizedCaseInsensitiveContains("permission")
            || message.localizedCaseInsensitiveContains("not authorized") {
            return .notAuthorized
        }
        if message.contains("超时") || message.localizedCaseInsensitiveContains("timed out")
            || message.localizedCaseInsensitiveContains("timeout") {
            return .timeout
        }
        if message.localizedCaseInsensitiveContains("no http")
            || message.localizedCaseInsensitiveContains("network")
            || message.localizedCaseInsensitiveContains("connect") {
            return .network
        }
        return .provider(message)
    }

    /// Whether an on-device fallback (future same-session audio reuse) could still
    /// salvage this session. `noSpeech` / `audioTooLong` / `notAuthorized` are terminal.
    public var isFallbackEligible: Bool {
        switch self {
        case .network, .timeout, .provider:
            return true
        case .noSpeech, .audioTooLong, .notAuthorized:
            return false
        }
    }

    public var userMessage: String {
        switch self {
        case .noSpeech: return "没听到语音,请再说一次。"
        case .audioTooLong: return "录音太长,请缩短后再试。"
        case .notAuthorized: return "未获授权。请检查麦克风 / 辅助功能权限。"
        case .network: return "网络不可用,云端识别失败。"
        case .timeout: return "识别超时,请重试。"
        case .provider(let message): return message
        }
    }
}
