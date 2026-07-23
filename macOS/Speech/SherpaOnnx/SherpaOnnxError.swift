import Foundation

/// 333 — typed failures for the sherpa-onnx native wrappers. The vendored C wrappers
/// previously `fatalError`'d when a C call returned nil (corrupt / half-downloaded model,
/// out-of-memory, internal library error), crashing the whole app from inside the audio
/// flow. They now `throw` these instead, so the capture services can catch and surface a
/// recoverable state (project rule: no `fatalError` in flows).
///
/// `LocalizedError` so the existing error-display paths (which read `localizedDescription`)
/// show the Chinese `userMessage` directly.
enum SherpaOnnxError: Error, LocalizedError, CustomStringConvertible {
    /// `SherpaOnnxCreateOfflineRecognizer` returned nil — model files unreadable/corrupt.
    case recognizerInitFailed
    /// `SherpaOnnxCreateOfflineStream` returned nil.
    case offlineStreamCreationFailed
    /// `SherpaOnnxGetOfflineStreamResult` returned nil.
    case offlineResultUnavailable
    /// `SherpaOnnxCreateOnlineStreamWithHotwords` returned nil.
    case onlineHotwordStreamCreationFailed
    /// `SherpaOnnxCreateCircularBuffer` returned nil.
    case circularBufferCreationFailed
    /// `SherpaOnnxCreateVoiceActivityDetector` returned nil.
    case vadCreationFailed
    /// `SherpaOnnxVoiceActivityDetectorFront` returned nil.
    case vadSegmentUnavailable

    /// User-facing, recoverable message (no internals, no file paths).
    var userMessage: String {
        switch self {
        case .recognizerInitFailed, .circularBufferCreationFailed, .vadCreationFailed:
            return "语音模型加载失败，可能未下载完整或文件损坏。请在设置中重新下载该模型。"
        case .offlineStreamCreationFailed, .offlineResultUnavailable, .vadSegmentUnavailable,
             .onlineHotwordStreamCreationFailed:
            return "语音识别引擎出错，请重试；若反复出现，请在设置中重新下载该模型。"
        }
    }

    var errorDescription: String? { userMessage }

    /// Stable diagnostic label (no user content).
    var description: String {
        switch self {
        case .recognizerInitFailed: return "SherpaOnnxError.recognizerInitFailed"
        case .offlineStreamCreationFailed: return "SherpaOnnxError.offlineStreamCreationFailed"
        case .offlineResultUnavailable: return "SherpaOnnxError.offlineResultUnavailable"
        case .onlineHotwordStreamCreationFailed: return "SherpaOnnxError.onlineHotwordStreamCreationFailed"
        case .circularBufferCreationFailed: return "SherpaOnnxError.circularBufferCreationFailed"
        case .vadCreationFailed: return "SherpaOnnxError.vadCreationFailed"
        case .vadSegmentUnavailable: return "SherpaOnnxError.vadSegmentUnavailable"
        }
    }
}
