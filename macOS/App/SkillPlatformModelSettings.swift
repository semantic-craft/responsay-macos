import Foundation

/// 技能平台（⌥L 法律/学术技能）的独立模型选择 — 同一提供商配置下的模型分流，不是第二套账户：
/// provider / 地域 / 套餐 / Base URL / Workspace ID / API Key 全部沿用「文本改写」卡的配置，
/// 只有 model 可被覆盖。
///
/// 持久化只使用 `byok.llm.<provider>.skillModel`。该选择必须保持 provider-scoped；读取
/// `byok.llm.skillModel` 这种无提供商身份的旧值会把另一提供商的模型发送到当前端点。
/// 空串或缺失 = **跟随听写模型**。
enum SkillPlatformModelSettings {
    static let suffix = "skillModel"

    /// 用户显式选择的技能平台模型；`nil` = 跟随听写模型。
    static func explicitModel(providerId: String, defaults: UserDefaults = .standard) -> String? {
        let stored = defaults.string(forKey: CapabilityProviderConfigStore.scopedKey(
            suffix, providerId: providerId, capability: .llm))
        guard let trimmed = stored?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    /// `nil` 或空串 = 恢复「跟随听写模型」。
    static func setExplicitModel(_ model: String?, providerId: String, defaults: UserDefaults = .standard) {
        defaults.set(
            model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            forKey: CapabilityProviderConfigStore.scopedKey(
                suffix, providerId: providerId, capability: .llm))
    }
}
