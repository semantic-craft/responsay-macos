import Foundation

extension ProviderConfigMachine {
    /// Project the settings surface from the same effective LLM snapshot used by the next
    /// runtime request. Raw unsupported values stay persisted until the user saves, but they no
    /// longer make the visible settings disagree with what either LLM lane will consume.
    func applyEffectiveLLMConfiguration(providerId requestedProviderId: String) {
        let lanes = ProviderConfigDispatcher(defaults: defaults, keyReader: keyReader)
            .resolveLLM(providerId: requestedProviderId)
        providerId = lanes.provider.providerId
        regionRaw = lanes.provider.region.rawValue
        planRaw = lanes.provider.plan.rawValue
        workspaceID = lanes.provider.workspaceID ?? ""
        baseURL = lanes.provider.baseURL
        model = lanes.dictationEndpoint.model
        skillModel = lanes.explicitSkillModel ?? ""
        apiKey = lanes.dictationEndpoint.apiKey ?? ""
    }
}
