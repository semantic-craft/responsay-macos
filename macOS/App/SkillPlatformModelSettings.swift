import Foundation

/// 技能平台（⌥L 法律/学术技能）的独立模型选择 — 同一提供商配置下的模型分流，不是第二套账户：
/// provider / 地域 / 套餐 / Base URL / Workspace ID / API Key 全部沿用「文本改写」卡的配置，
/// 只有 model 可被覆盖。
///
/// 持久化沿用 `CapabilityProviderConfigStore` 的双写模式（`byok.llm.<provider>.skillModel`
/// scoped + `byok.llm.skillModel` active 镜像）。回退顺序（可测试）：
///   scoped key → （该 provider 为当前激活时）active key → nil。
/// 空串或缺失 = **跟随听写模型** —— 旧配置没有该字段时行为与升级前完全一致，不产生静默费用变化。
enum SkillPlatformModelSettings {
    static let suffix = "skillModel"

    /// 用户显式选择的技能平台模型；`nil` = 跟随听写模型。
    static func explicitModel(providerId: String, defaults: UserDefaults = .standard) -> String? {
        let stored = CapabilityProviderConfigStore.string(
            suffix, providerId: providerId, capability: .llm, defaults: defaults,
            activeProviderId: defaults.string(forKey: CapabilityProviderConfigStore.activeKey("provider", capability: .llm)))
        guard let trimmed = stored?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    /// `nil` 或空串 = 恢复「跟随听写模型」。
    static func setExplicitModel(_ model: String?, providerId: String, defaults: UserDefaults = .standard) {
        CapabilityProviderConfigStore.set(
            model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            suffix: suffix, providerId: providerId, capability: .llm, defaults: defaults,
            activeProviderId: defaults.string(forKey: CapabilityProviderConfigStore.activeKey("provider", capability: .llm)))
    }
}
