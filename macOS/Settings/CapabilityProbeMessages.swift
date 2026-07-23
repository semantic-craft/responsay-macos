import Foundation
import ResponsayCore

enum CapabilityProbeMessages {
    static func websocketStatus(
        fetch: Bool,
        providerId: String,
        capability: ModelCapability,
        appId: String,
        accessToken: String,
        model: String
    ) -> String {
        if fetch {
            return "此服务不支持拉取模型列表"
        }
        return "✓ 配置格式有效（WebSocket 服务）"
    }

    static func llmValidationStatus(_ error: LLMError) -> String {
        switch error {
        case .notConfigured: return "请先填 Base URL / Model / 密钥"
        case .invalidEndpoint: return "URL 无效"
        case .http(let status, _): return "HTTP \(status)（检查密钥权限或模型名）"
        case .emptyContent: return "✓ 已连接（模型未回内容）"
        case .network: return "连接失败"
        case .badJSON: return "✓ 已连接 · 模型可用"
        case .invalidConfiguration(let message): return message
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
