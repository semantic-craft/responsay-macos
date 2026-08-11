import Foundation
import Observation
import ResponsayCore

/// Deterministic provider-config logic extracted out of `CapabilityCardView` so the
/// plan→model routing, endpoint picking, keychain reads/writes and connection probe can be
/// unit-tested without rendering any SwiftUI, and shared by the ASR / LLM / TTS panes.
///
/// Behaviour is identical to the pre-extraction view: same `CapabilityProviderConfigStore`
/// keys, same `CapabilityCredentialAccount` keychain accounts (ADR-0023: BYOK keys are read
/// on load / provider-switch and written on change, never stored in UserDefaults / plaintext),
/// same effective provider configuration consumed by the next ASR capture.
///
/// `defaults` is injectable purely so tests can drive a fresh suite; production always uses
/// `.standard`, so runtime behaviour is unchanged.
@MainActor
@Observable
final class ProviderConfigMachine {
    let capability: ModelCapability
    let preferredProviderId: String?

    // Observable config state (was the view's @State). Several fields are read/written by the
    // probe extension too.
    var providerId = ""
    var regionRaw = ""
    var planRaw = ""
    var model = ""
    /// LLM only — 技能平台模型；空串 = 跟随听写模型（`SkillPlatformModelSettings` 同一约定）。
    var skillModel = ""
    var voice = ""
    var baseURL = ""
    var workspaceID = ""
    var apiKey = ""
    var appId = ""
    var accessToken = ""
    var boostingTableId = ""
    var precompiledVocabularyID = ""
    var precompiledVocabularyBinding: QwenPrecompiledVocabularyBinding?
    var status = ""
    var fetchedModels: [String] = []

    @ObservationIgnored private var loaded = false
    @ObservationIgnored let defaults: UserDefaults
    @ObservationIgnored let keyReader: (String) -> String?
    @ObservationIgnored private let keyWriter: (String, String) -> Void

    init(
        capability: ModelCapability,
        preferredProviderId: String?,
        defaults: UserDefaults = .standard,
        keyReader: @escaping (String) -> String? = { BYOKKeychain.read($0) },
        keyWriter: @escaping (String, String) -> Void = { BYOKKeychain.write($0, account: $1) }
    ) {
        self.capability = capability
        self.preferredProviderId = preferredProviderId
        self.defaults = defaults
        self.keyReader = keyReader
        self.keyWriter = keyWriter
    }

    // MARK: Derived

    var presets: [ProviderPreset] { ProviderCatalog.presets(for: capability).filter { !$0.isLocal } }

    var current: ProviderPreset {
        presets.first { $0.id == providerId } ?? presets.first ?? ProviderCatalog.custom
    }

    /// Whether the loaded provider has a usable credential, in the two shapes `ResolvedProviderConfig`
    /// recognises. Reads the already-loaded in-memory fields, so callers get this without a second
    /// Keychain round-trip.
    var hasStoredCredential: Bool {
        !apiKey.isEmpty || (!appId.isEmpty && !accessToken.isEmpty)
    }

    /// 豆包流式 hardcodes its WSS endpoint + model in code (VolcengineRealtimeEndpoint) and ignores
    /// the card's Base URL / 模型 ID. Show those fields read-only for it so the card can't display a
    /// stale batch config. (千问 left this set when its card moved from the retired OmniRealtime
    /// socket to the 非实时 HTTP endpoint, whose host and model *are* configurable.)
    var isFixedEndpoint: Bool {
        capability == .asr && providerId == "volcengine-flash"
    }

    var isQwenLLM: Bool { capability == .llm && providerId == "qwen" }

    /// 百炼 非实时语音识别 card — same 业务空间专属域名 story as the LLM card, different path.
    var isQwenASRFlash: Bool { capability == .asr && providerId == QwenASRFlashRouting.providerId }

    /// Both 百炼 cards offer the optional Workspace ID; every other provider hides the row.
    var showsWorkspaceIDField: Bool { isQwenLLM || isQwenASRFlash }

    var qwenWorkspaceBaseURL: String? {
        if isQwenLLM {
            return QwenWorkspaceEndpoint.baseURL(workspaceID: workspaceID, region: region)
        }
        if isQwenASRFlash {
            return QwenWorkspaceEndpoint.asrBaseURL(workspaceID: workspaceID, region: region)
        }
        return nil
    }

    var usesQwenWorkspaceEndpoint: Bool { qwenWorkspaceBaseURL != nil }

    var workspaceIDValidationMessage: String? {
        guard showsWorkspaceIDField else { return nil }
        let trimmed = workspaceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, QwenWorkspaceEndpoint.normalizedWorkspaceID(trimmed) == nil else { return nil }
        return "格式应为 ws- 后接字母或数字；请只填 Workspace ID，不要填完整 Host。"
    }

    var qwenWorkspaceHelp: String {
        if isQwenASRFlash {
            return "留空使用仍兼容的通用域名；填写后按接入点生成业务空间专属识别地址。"
        }
        switch region {
        case .unitedStates:
            return "美国（弗吉尼亚）按文档使用 dashscope-us 通用域名，不拼接 Workspace ID。"
        case .germany, .japan:
            return "此接入点须填写 Workspace ID，应用会生成对应地域的专属 Responses 地址。"
        default:
            return "留空使用仍兼容的通用域名；填写后按接入点生成业务空间专属 Responses 地址。"
        }
    }

    var currentRegions: [ProviderRegion] { current.regions(for: capability) }
    var currentPlans: [BillingPlan] { current.plans(for: capability) }
    var region: ProviderRegion { ProviderRegion(rawValue: regionRaw) ?? currentRegions.first ?? .global }
    var plan: BillingPlan {
        let candidate = BillingPlan(rawValue: planRaw) ?? currentPlans.first ?? .payg
        return currentPlans.contains(candidate) ? candidate : (currentPlans.first ?? .payg)
    }

    /// All non-empty endpoints (region × plan) for this capability, shown in one combined
    /// 「接入点」dropdown so 按量付费 / Token Plan sit next to 国内/新加坡/欧洲 instead of being
    /// separate providers (the Base URL below follows the pick).
    var endpointChoices: [EndpointVariant] {
        current.endpoints(for: capability).filter { !$0.baseURL.isEmpty || isQwenLLM }
    }

    // MARK: Lifecycle

    func load() {
        guard !loaded else { return }
        loaded = true
        let storedProvider = defaults.string(forKey: CapabilityProviderConfigStore.providerKey(capability))
        var pid = preferredProviderId ?? storedProvider ?? defaultProviderId()
        if !presets.contains(where: { $0.id == pid }) { pid = defaultProviderId() }
        applyEffectiveConfiguration(providerId: pid)
        boostingTableId = defaults.string(forKey: "byok.\(providerId).boostingTableId") ?? ""
        loadQwenPrecompiledVocabulary()
    }

    func defaultProviderId() -> String {
        if presets.contains(where: { $0.id == "qwen" }) { return "qwen" }
        return presets.first?.id ?? "custom"
    }

    func selectProvider() {
        ProviderConfigDispatcher(defaults: defaults, keyReader: keyReader)
            .selectProvider(providerId, capability: capability)
        applyEffectiveConfiguration(providerId: providerId)
        boostingTableId = defaults.string(forKey: "byok.\(providerId).boostingTableId") ?? ""
        loadQwenPrecompiledVocabulary()
        status = ""
        fetchedModels = []
    }

    func endpointBase() -> String {
        // 千问实时: always the derived socket (接入点 + Workspace ID), never a stored value.
        if isQwenASRFlash {
            return QwenASRFlashRouting.displayBaseURL(workspaceID: workspaceID, region: region)
        }
        return qwenWorkspaceBaseURL
            ?? current.endpoint(for: capability, region: region, plan: plan)?.baseURL
            ?? baseURL
    }

    func refreshBaseURLForSelection() {
        baseURL = endpointBase()
    }

    /// Load the API key stored for the current plan. 按量付费 and Token Plan keep separate keys
    /// (sk- vs tp-), so switching the 接入点 dropdown shows that plan's key (or blank) instead
    /// of carrying the other plan's key over and sending it to the wrong host → 401.
    func reloadKeyForCurrentPlan() {
        apiKey = readApiKey(providerId: providerId, plan: plan)
    }

    /// When the billing plan changes and the user hasn't customized the model away from the old
    /// plan's default, retarget it to the new plan's default. No-op when both plans share a default
    /// (MiMo plans currently share the mimo-v2.5 default).
    func autoSwitchModel(from oldPlanRaw: String, to newPlanRaw: String) {
        guard let oldPlan = BillingPlan(rawValue: oldPlanRaw),
              let newPlan = BillingPlan(rawValue: newPlanRaw),
              oldPlan != newPlan,
              let newDefault = current.defaultModel(for: capability, plan: newPlan)
        else { return }
        if model.isEmpty || model == current.defaultModel(for: capability, plan: oldPlan) {
            model = newDefault
        }
    }

    // MARK: Persistence

    func persist() {
        setScoped(regionRaw, suffix: "region")
        setScoped(planRaw, suffix: "plan")
        setScoped(model, suffix: "model")
        if capability == .llm {
            SkillPlatformModelSettings.setExplicitModel(
                skillModel,
                providerId: providerId,
                defaults: defaults)
        }
        setScoped(voice, suffix: "voice")
        setScoped(baseURL, suffix: "baseURL")
        if showsWorkspaceIDField {
            setScoped(workspaceID.trimmingCharacters(in: .whitespacesAndNewlines), suffix: "workspaceId")
        }
        ModelConfigurationEvents.post()
    }

    func setScoped(_ value: Any, suffix: String) {
        CapabilityProviderConfigStore.set(
            value, suffix: suffix, providerId: providerId, capability: capability,
            defaults: defaults)
    }

    // MARK: Credential writers (keychain — ADR-0023, never stored in UserDefaults/plaintext)

    func writeApiKey() {
        keyWriter(
            apiKey,
            CapabilityCredentialAccount.apiKeyAccount(
                providerId: providerId, capability: capability, plan: plan))
    }

    func writeAppId() {
        keyWriter(appId, CapabilityCredentialAccount.appIdAccount(providerId: providerId))
    }

    func writeAccessToken() {
        keyWriter(
            accessToken,
            CapabilityCredentialAccount.accessTokenAccount(providerId: providerId))
    }

    func writeBoostingTableId() {
        defaults.set(
            boostingTableId.trimmingCharacters(in: .whitespacesAndNewlines),
            forKey: "byok.\(providerId).boostingTableId")
    }

    private func readApiKey(providerId: String, plan: BillingPlan) -> String {
        let account = CapabilityCredentialAccount.apiKeyAccount(
            providerId: providerId, capability: capability, plan: plan)
        return keyReader(account) ?? ""
    }

    private func applyEffectiveConfiguration(providerId requestedProviderId: String) {
        let dispatcher = ProviderConfigDispatcher(defaults: defaults, keyReader: keyReader)
        if capability == .llm {
            let lanes = dispatcher.resolveLLM(providerId: requestedProviderId)
            apply(lanes.provider)
            model = lanes.dictationEndpoint.model
            skillModel = lanes.explicitSkillModel ?? ""
        } else {
            apply(dispatcher.resolve(capability, providerId: requestedProviderId))
            skillModel = ""
        }
    }

    private func apply(_ effective: ResolvedProviderConfig) {
        providerId = effective.providerId
        regionRaw = effective.region.rawValue
        planRaw = effective.plan.rawValue
        model = effective.model
        voice = effective.voice ?? ""
        baseURL = effective.baseURL
        workspaceID = showsWorkspaceIDField ? (effective.workspaceID ?? "") : ""
        apiKey = effective.apiKey ?? ""
        appId = effective.appId ?? ""
        accessToken = effective.accessToken ?? ""
    }

}
