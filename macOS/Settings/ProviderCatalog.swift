import Foundation
import SwiftUI
import ResponsayCore

/// Verified provider presets that pre-fill the (always editable) BYOK fields in
/// `ModelsKeysPane`. Pattern mirrors OpenLess "Services": pick a preset → its
/// Base URL / Model / key-label are filled in but the user can edit any of them,
/// pick 「自定义」, or add multiple custom endpoints. Nothing here is a hard lock.
///
/// Public provider endpoint presets used by Settings.
/// No secrets live here — only public base URLs + default model ids.

// MARK: - Axes

enum ModelCapability: String, CaseIterable, Identifiable, Sendable {
    case asr, llm, tts
    public var id: String { rawValue }
    var title: String {
        switch self {
        case .asr: "云端语音模型配置"
        case .llm: "服务凭证配置 (大语言模型)"
        case .tts: "服务凭证配置 (语音合成)"
        }
    }
    var connectionTitle: LocalizedStringKey {
        switch self {
        case .asr: "云端识别连接配置"
        case .llm: "云端文本模型连接配置"
        case .tts: "云端朗读连接配置"
        }
    }
}

/// 区域 — changes the host. Only surfaced when a provider has more than one.
enum ProviderRegion: String, CaseIterable, Sendable {
    case china, singapore, unitedStates, germany, japan, europe, intl, global
    var label: String {
        switch self {
        case .china: "国内"
        case .singapore: "新加坡"
        case .unitedStates: "美国（弗吉尼亚）"
        case .germany: "德国（法兰克福）"
        case .japan: "日本（东京）"
        case .europe: "欧洲"
        case .intl: "海外"
        case .global: "全球"
        }
    }
}

/// 计费 — for providers where the endpoint *and* key format differ by plan
/// (verified: MiMo Token Plan). Only surfaced when a provider has both.
enum BillingPlan: String, CaseIterable, Sendable {
    case payg, package
    var label: String {
        switch self {
        case .payg: "按量付费"
        case .package: "Token Plan"
        }
    }
}

enum CredentialShape: Sendable {
    case apiKey
    case appIdAndToken
}

/// Builds the dedicated OpenAI-compatible Responses base URL for one Qwen business workspace.
/// Workspace IDs become a DNS label, so accept only the documented `ws-…` shape instead of
/// interpolating arbitrary user input into a host.
enum QwenWorkspaceEndpoint {
    static func normalizedWorkspaceID(_ rawValue: String) -> String? {
        let candidate = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard candidate.hasPrefix("ws-"), candidate.count > 3, candidate.count <= 63 else { return nil }
        let suffix = candidate.dropFirst(3)
        guard suffix.unicodeScalars.allSatisfy({ scalar in
            (48 ... 57).contains(scalar.value) || (97 ... 122).contains(scalar.value)
        }) else { return nil }
        return candidate
    }

    static func baseURL(workspaceID: String, region: ProviderRegion) -> String? {
        guard let workspaceID = normalizedWorkspaceID(workspaceID) else { return nil }
        let regionHost: String
        switch region {
        case .china:
            regionHost = "cn-beijing"
        case .singapore:
            regionHost = "ap-southeast-1"
        case .germany:
            regionHost = "eu-central-1"
        case .japan:
            regionHost = "ap-northeast-1"
        case .unitedStates, .europe, .intl, .global:
            return nil
        }
        return "https://\(workspaceID).\(regionHost).maas.aliyuncs.com/compatible-mode/v1"
    }
}

// MARK: - Preset model

struct EndpointVariant: Sendable {
    let region: ProviderRegion
    let plan: BillingPlan
    let baseURL: String
    /// e.g. realtime wss endpoint, or `[待核]` notes.
    let note: String?

    init(_ region: ProviderRegion, _ plan: BillingPlan, _ baseURL: String, note: String? = nil) {
        self.region = region
        self.plan = plan
        self.baseURL = baseURL
        self.note = note
    }
}

struct PresetVoice: Identifiable, Sendable {
    let id: String
    let displayName: String
}

struct ProviderPreset: Identifiable, Sendable {
    let id: String
    let displayName: String
    let capabilities: Set<ModelCapability>
    let credentialShape: CredentialShape
    let endpoints: [EndpointVariant]
    let capabilityEndpoints: [ModelCapability: [EndpointVariant]]
    let defaultModels: [ModelCapability: String]
    let keyLabel: String
    /// Shown next to the key field to prevent mis-billing (e.g. `sk-sp-…`).
    let keyFormatHint: String?
    let capabilityKeyFormatHints: [ModelCapability: String]
    /// Can call web search via the API → 来源核验「URL 直查」可复用。
    let builtinSearch: Bool
    let isCustom: Bool
    let isLocal: Bool
    /// Known model ids per capability — drives the "选择模型" menu so it offers the
    /// *right* capability's models (e.g. MiniMax TTS voices, not its chat models),
    /// instead of relying on a `/models` ping that returns chat models. Editable
    /// field stays; this is just the curated dropdown.
    var presetModels: [ModelCapability: [String]] = [:]
    /// Known voices for TTS (语音合成), driving the "音色" picker menu.
    var presetVoices: [PresetVoice] = []

    init(
        id: String,
        displayName: String,
        capabilities: Set<ModelCapability>,
        credentialShape: CredentialShape,
        endpoints: [EndpointVariant],
        capabilityEndpoints: [ModelCapability: [EndpointVariant]] = [:],
        defaultModels: [ModelCapability: String],
        keyLabel: String,
        keyFormatHint: String?,
        capabilityKeyFormatHints: [ModelCapability: String] = [:],
        builtinSearch: Bool,
        isCustom: Bool,
        isLocal: Bool,
        presetModels: [ModelCapability: [String]] = [:],
        presetVoices: [PresetVoice] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.capabilities = capabilities
        self.credentialShape = credentialShape
        self.endpoints = endpoints
        self.capabilityEndpoints = capabilityEndpoints
        self.defaultModels = defaultModels
        self.keyLabel = keyLabel
        self.keyFormatHint = keyFormatHint
        self.capabilityKeyFormatHints = capabilityKeyFormatHints
        self.builtinSearch = builtinSearch
        self.isCustom = isCustom
        self.isLocal = isLocal
        self.presetModels = presetModels
        self.presetVoices = presetVoices
    }

    func displayName(for capability: ModelCapability) -> String {
        switch capability {
        case .asr:
            return asrDisplayName
        case .llm, .tts:
            return commonDisplayName
        }
    }

    private var asrDisplayName: String {
        switch id {
        case "qwen-asr-flash":
            return "阿里云百炼 · 千问极速实时"
        case "volcengine-flash":
            return "火山引擎 · 豆包流式"
        case "volcengine-tts":
            return "火山引擎"
        default:
            return commonDisplayName
        }
    }

    private var commonDisplayName: String {
        switch id {
        case "qwen":
            return "阿里云百炼"
        case "mimo":
            return "小米Mimo"
        case "zhipu":
            return "智谱GLM"
        case "apple":
            return "Apple 系统原生"
        default:
            return displayName
        }
    }

    private func uniqueRegions(_ source: [EndpointVariant]) -> [ProviderRegion] {
        var seen: [ProviderRegion] = []
        for e in source where !seen.contains(e.region) { seen.append(e.region) }
        return seen
    }

    private func uniquePlans(_ source: [EndpointVariant]) -> [BillingPlan] {
        var seen: [BillingPlan] = []
        for e in source where !seen.contains(e.plan) { seen.append(e.plan) }
        return seen
    }

    var regions: [ProviderRegion] { uniqueRegions(endpoints) }
    func regions(for capability: ModelCapability) -> [ProviderRegion] {
        uniqueRegions(endpoints(for: capability))
    }
    var plans: [BillingPlan] { uniquePlans(endpoints) }
    func plans(for capability: ModelCapability) -> [BillingPlan] {
        uniquePlans(endpoints(for: capability))
    }
    func endpoints(for capability: ModelCapability) -> [EndpointVariant] {
        let scoped = capabilityEndpoints[capability] ?? []
        return scoped.isEmpty ? endpoints : scoped
    }
    func endpoint(region: ProviderRegion, plan: BillingPlan) -> EndpointVariant? {
        endpoints.first { $0.region == region && $0.plan == plan }
            ?? endpoints.first { $0.region == region }
            ?? endpoints.first
    }
    func endpoint(for capability: ModelCapability, region: ProviderRegion, plan: BillingPlan) -> EndpointVariant? {
        let scoped = endpoints(for: capability)
        return scoped.first { $0.region == region && $0.plan == plan }
            ?? scoped.first { $0.region == region }
            ?? scoped.first
    }
    func keyFormatHint(for capability: ModelCapability) -> String? {
        capabilityKeyFormatHints[capability] ?? keyFormatHint
    }
    func defaultModel(for capability: ModelCapability, plan _: BillingPlan) -> String? {
        defaultModels[capability]
    }
    func presets(for capability: ModelCapability) -> Bool { capabilities.contains(capability) }
}

// MARK: - Registry

enum ProviderCatalog {

    /// All cloud + local presets. Capability pickers apply their own display
    /// order so cloud models stay above local/offline choices.
    static let all: [ProviderPreset] = [qwen, qwenASRRealtime, doubao, volcengineFlash, volcengineTTS, mimo, zhipu, minimax, deepseek,
                                         openAI, gemini,
                                         custom, appleLocal]

    /// Presets offering a given capability (for that capability's provider picker).
    static func presets(for capability: ModelCapability) -> [ProviderPreset] {
        let rank = Dictionary(uniqueKeysWithValues: (displayOrder[capability] ?? []).enumerated().map { ($0.element, $0.offset) })
        return all
            .filter { $0.capabilities.contains(capability) }
            .sorted { lhs, rhs in
                let left = rank[lhs.id] ?? Int.max
                let right = rank[rhs.id] ?? Int.max
                if left != right { return left < right }
                return lhs.displayName < rhs.displayName
            }
    }

    /// True when a provider offers more than one billing plan for a capability (按量付费 vs
    /// Token Plan). Those plans use different keys (sk- vs tp-), so the key is stored per
    /// plan — see `CapabilityCredentialAccount.apiKeyAccount`.
    static func providerHasMultipleBillingPlans(_ providerId: String, capability: ModelCapability) -> Bool {
        guard let preset = all.first(where: { $0.id == providerId }) else { return false }
        return preset.plans(for: capability).count > 1
    }

    private static let displayOrder: [ModelCapability: [String]] = [
        .asr: ["qwen-asr-flash", "volcengine-flash", "mimo", "openai", "gemini", "custom", "apple"],
        .llm: ["qwen", "doubao", "mimo", "zhipu", "deepseek", "gemini", "openai", "custom"],
        .tts: ["qwen", "volcengine-tts", "mimo", "minimax", "openai", "gemini", "custom"],
    ]
}
