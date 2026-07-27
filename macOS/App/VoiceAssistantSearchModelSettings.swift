import Foundation
import ResponsayCore

/// 任意提问「联网搜索」的专属模型选择 + 候选解析。
///
/// 联网搜索只对 Qwen(百炼/DashScope) / 智谱 / 小米Mimo 三家的 `/chat/completions` 生效
/// (见 `LLMSearchControl`)。开了搜索却用不支持联网的主模型时，提问会被静默退回普通问答、
/// 只能答到训练截止——所以把搜索这一问路由到一个**可联网的专属模型**(用户已配好密钥的)，
/// 与主对话模型解耦。用户拍板:开搜索时由这个联网模型直接回答(不二段式)。
///
/// 纯 UserDefaults + `ProviderCatalog`(纯数据)逻辑，**不读钥匙串**——可安全用于 SwiftUI body
/// 与单测;真正"哪家配了密钥"的判断留到 `LLMEndpointResolver.resolveSearch`(在主线程渲染路径
/// 之外的 capture controller 里跑)。
enum VoiceAssistantSearchModelSettings {
    /// 存的偏好 provider id;"" 或任何非可联网值 = 自动。
    static let key = "voiceAssistant.searchProvider"

    /// 支持联网搜索的 provider(canonical id)。顺序 = 自动模式的回退优先级。
    /// Qwen/智谱/MiMo 走 `/chat/completions` + `LLMSearchControl`;doubao(火山方舟)与 openai 的联网
    /// 只在 `/responses` 上,由 `DirectArkResponsesStreamingClient` 驱动(见 CaptureController+AskAnything)。
    static let searchProviders = ["qwen", "zhipu", "mimo", "doubao", "openai"]

    /// 用户显式选择;自动 / 非法存值 → nil。
    static func preferredProviderId(defaults: UserDefaults = .standard) -> String? {
        let stored = defaults.string(forKey: key) ?? ""
        return searchProviders.contains(stored) ? stored : nil
    }

    /// 要尝试的 provider 顺序:偏好的排第一(若有)，其余按默认顺序补齐。
    static func orderedCandidates(defaults: UserDefaults = .standard) -> [String] {
        guard let preferred = preferredProviderId(defaults: defaults) else { return searchProviders }
        return [preferred] + searchProviders.filter { $0 != preferred }
    }

    /// 面向用户的 provider 名(如「阿里云百炼」/「智谱GLM」/「小米Mimo」)。
    static func displayName(for providerId: String) -> String {
        ProviderCatalog.presets(for: .llm).first { $0.id == providerId }?.displayName(for: .llm) ?? providerId
    }

    /// 胶囊里露出的「联网模型署名」(对应设计稿 ask-anything-capsule Variant B):单字纹章 + 友好名。
    /// 名字用模型品牌(通义千问/智谱/MiMo),比 provider 公司名更贴近用户认知。非可联网 → nil。
    /// 走独立检索服务时,署名的是检索服务本身(豆包搜索 / Perplexity)——搜的是它,不是主模型。
    static func capsuleSource(for providerId: String) -> CapsuleSearchSource? {
        if let kind = WebSearchBackendKind(rawValue: providerId) {
            return CapsuleSearchSource(monogram: kind.monogram, name: kind.displayName)
        }
        switch providerId {
        case "qwen":   return CapsuleSearchSource(monogram: "通", name: "通义千问")
        case "zhipu":  return CapsuleSearchSource(monogram: "智", name: "智谱")
        case "mimo":   return CapsuleSearchSource(monogram: "Mi", name: "MiMo")
        case "doubao": return CapsuleSearchSource(monogram: "豆", name: "豆包")
        case "openai": return CapsuleSearchSource(monogram: "O", name: "OpenAI")
        default:       return nil
        }
    }
}

/// 联网搜索模型署名(monogram + 友好名),供胶囊浮标签 chip 与回答卡使用。
struct CapsuleSearchSource: Equatable {
    let monogram: String
    let name: String
}
