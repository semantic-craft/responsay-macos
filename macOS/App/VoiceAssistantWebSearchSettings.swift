import Foundation
import ResponsayCore

enum VoiceAssistantWebSearchSettings {
    static let key = "voiceAssistant.webSearchEnabled"

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key)
    }

    static func isSupported(endpoint: LLMEndpoint?) -> Bool {
        guard let endpoint, !endpoint.isLocal else { return false }
        return LLMSearchControl.supportsSearch(
            providerId: endpoint.providerId,
            model: endpoint.model,
            baseURLHost: endpoint.host)
    }

    /// 模型自带联网这一档是否生效。
    ///
    /// 配了独立检索服务(`WebSearchProviderSettings`)时恒为 false:联网那一步已经由 App 的
    /// 检索段做掉了,再打开模型自带联网会让同一个问题被搜两遍(还会搅乱来源署名)。
    /// 重新生成走的 `makeClient` 靠这个判断,不能漏。
    static func effectiveEnabled(
        endpoint: LLMEndpoint?,
        defaults: UserDefaults = .standard,
        keyReader: (String) -> String? = { BYOKKeychain.read($0) }
    ) -> Bool {
        guard WebSearchProviderSettings.backend(defaults: defaults, reader: keyReader) == nil else {
            return false
        }
        return isEnabled(defaults: defaults) && isSupported(endpoint: endpoint)
    }
}
