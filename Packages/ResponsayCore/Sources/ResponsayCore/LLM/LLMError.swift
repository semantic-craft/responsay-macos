import Foundation

/// Errors from the App-direct LLM path — the app calls a BYOK provider (or a local runner)
/// straight, with no backend hop (epic 238, started in tracer 239).
public enum LLMError: LocalizedError, Equatable {
    case notConfigured                 // missing base URL / model / key
    case invalidEndpoint(String)       // base URL didn't form a URL
    case network(String)
    case http(status: Int, body: String)
    case emptyContent                  // 2xx but no usable text content
    case badJSON(String)               // content wasn't the expected JSON envelope
    case invalidConfiguration(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "未配置模型(缺 Base URL / 模型 / 密钥)。请在「模型与密钥」里选好服务方并填密钥。"
        case .invalidEndpoint(let s):
            return "端点无效:\(s)"
        case .network(let m):
            return "网络错误:\(m)"
        case .http(let status, let body):
            let snippet = body.prefix(200)
            return "服务商返回 HTTP \(status)。\(snippet.isEmpty ? "请检查密钥权限或端点。" : String(snippet))"
        case .emptyContent:
            return "模型没有返回内容。"
        case .badJSON(let m):
            return "无法解析模型输出:\(m)"
        case .invalidConfiguration(let message):
            return "模型配置错误:\(message)"
        }
    }
}
