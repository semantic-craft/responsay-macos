import Foundation

// MARK: - Cloud OCR · shared typed error
//
// Mistral and Baidu share the same failure surface, so they throw one error type rather than two
// near-identical per-provider enums. `LocalizedError` so the macOS controller's
// `error.localizedDescription` surfaces a real Chinese message (not "CloudOCRError error 2") when it
// shows `.failed(message)`. The on-device path keeps using `OCRError` (recognitionFailed) — this is
// only for BYOK cloud providers.

public enum CloudOCRError: Error, Equatable, LocalizedError {
    /// API Key / 凭据未填 — never hits the network.
    case notConfigured
    /// Screenshot → bytes / request construction failed.
    case encoding
    /// Non-2xx HTTP (401/403 key invalid, 429 rate-limit, 5xx server).
    case http(Int)
    /// Baidu access_token exchange failed (carries the upstream reason).
    case token(String)
    /// OCR endpoint returned a business error code (Baidu `error_code`).
    case api(code: Int, message: String?)
    /// Response had no usable text → caller shows the "未识别到文字" guidance.
    case emptyText

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "未配置该 OCR 服务的 API Key，请在「设置 › 图片识别」中填写，或切回 Apple Vision（本机）。"
        case .encoding:
            return "截图编码失败，无法上送识别。"
        case let .http(status):
            switch status {
            case 401, 403:
                return "鉴权失败（HTTP \(status)）：API Key 无效或已过期。"
            case 429:
                return "请求过于频繁（HTTP 429），请稍后再试。"
            default:
                return "OCR 请求失败（HTTP \(status)）。"
            }
        case let .token(reason):
            return "百度鉴权失败：\(reason)"
        case let .api(code, message):
            if let message, !message.isEmpty {
                return "OCR 接口返回错误（\(code)）：\(message)"
            }
            return "OCR 接口返回错误（错误码 \(code)）。"
        case .emptyText:
            return "未识别到文字。"
        }
    }
}
