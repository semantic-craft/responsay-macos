import Foundation
import ResponsayCore

/// Readiness of one model option (a menu choice or the current selection).
/// Single source for the 设置·模型 panel pills (378), the menu-bar jump-to-config
/// decision (379), and the overview status strip (382) — the three surfaces never
/// drift on "configured or not".
enum ModelLaneReadiness: Equatable, Sendable {
    /// On-device engine with every required file available.
    case local
    /// On-device engine selected, but its model files are not installed yet.
    case localNotInstalled
    /// Cloud provider with a BYOK key on file.
    case cloudReady
    /// Cloud provider with no key yet — speaking would hit a silent failure, so
    /// the UI nudges the user to configure it.
    case cloudUnconfigured

    var isReady: Bool { self == .local || self == .cloudReady }
    var needsConfiguration: Bool { self == .cloudUnconfigured || self == .localNotInstalled }
}

enum ModelLaneReadinessReason: String, Equatable, Sendable {
    case ready
    case modelNotInstalled
    case missingCredential
    case invalidEndpoint
    case missingModel
    case invalidRoute

    var title: String {
        switch self {
        case .ready: "已就绪"
        case .modelNotInstalled: "本机模型未下载"
        case .missingCredential: "未配置 · 去填密钥"
        case .invalidEndpoint: "端点无效 · 去配置"
        case .missingModel: "模型 ID 为空 · 去配置"
        case .invalidRoute: "模型路由无效 · 去配置"
        }
    }

    var detail: String {
        switch self {
        case .ready: ""
        case .modelNotInstalled: "下载后即可离线使用"
        case .missingCredential: "该云端模型还没有密钥，现在配置后即可使用"
        case .invalidEndpoint: "请填写包含协议与主机名的有效服务端点"
        case .missingModel: "请填写该服务实际使用的模型 ID"
        case .invalidRoute: "当前模型路由已失效，请重新选择服务"
        }
    }
}

struct ModelLaneState: Equatable, Sendable {
    let readiness: ModelLaneReadiness
    let reason: ModelLaneReadinessReason

    static let localReady = Self(readiness: .local, reason: .ready)
    static let localMissing = Self(readiness: .localNotInstalled, reason: .modelNotInstalled)
}

/// Resolves the readiness of an ASR / LLM / TTS / OCR option. Pure given an injected
/// `ProviderConfigDispatcher` (which carries its own defaults + Keychain reader) and an
/// OCR key reader (OCR isn't a `ModelCapability`, so its keys live in `OCRCredentialAccount`),
/// so it unit-tests without the real Keychain. Mirrors `OverviewScreen.providerStatus`'s
/// `isLocal || hasKey` rule — zero new readiness logic, just per-option resolution.
struct ModelLaneReadinessResolver {
    private let dispatcher: ProviderConfigDispatcher
    private let ocrKeyReader: (String) -> String?
    private let asrLocalInstalled: (LocalModelSpec) -> Bool
    private let ttsLocalInstalled: () -> Bool
    private let ocrLocalInstalled: () -> Bool

    init(
        dispatcher: ProviderConfigDispatcher = ProviderConfigDispatcher(),
        ocrKeyReader: @escaping (String) -> String? = { BYOKKeychain.read($0) },
        asrLocalInstalled: @escaping (LocalModelSpec) -> Bool = { $0.isInstalled },
        ttsLocalInstalled: @escaping () -> Bool = { LocalModelSpec.kokoroMultiLangV1_1.isInstalled },
        ocrLocalInstalled: @escaping () -> Bool = { LocalModelRegistry.defaultOCR.isInstalled }
    ) {
        self.dispatcher = dispatcher
        self.ocrKeyReader = ocrKeyReader
        self.asrLocalInstalled = asrLocalInstalled
        self.ttsLocalInstalled = ttsLocalInstalled
        self.ocrLocalInstalled = ocrLocalInstalled
    }

    /// `optionId` is an `ASREngine.rawValue`, optionally plan-tagged (`cloud-mimo#package`).
    func asr(optionId raw: String) -> ModelLaneReadiness {
        asrState(optionId: raw).readiness
    }

    func asrState(optionId raw: String) -> ModelLaneState {
        let (base, plan) = ModelRouteOptionID.parse(raw)
        guard let engine = ASREngine.fromStoredValue(base) else {
            return ModelLaneState(readiness: .cloudUnconfigured, reason: .invalidRoute)
        }
        if engine == .apple { return .localReady }
        if let spec = ASRFallback.offlineSpec(for: engine) {
            return asrLocalInstalled(spec) ? .localReady : .localMissing
        }
        guard let providerId = engine.associatedProviderId else {
            return ModelLaneState(readiness: .cloudUnconfigured, reason: .invalidRoute)
        }
        return cloud(.asr, providerId: providerId, plan: plan)
    }

    /// `optionId` is an LLM provider id (optionally plan-tagged, `mimo#package`).
    func llm(optionId id: String) -> ModelLaneReadiness {
        llmState(optionId: id).readiness
    }

    func llmState(optionId id: String) -> ModelLaneState {
        let (base, plan) = ModelRouteOptionID.parse(id)
        return cloud(.llm, providerId: base, plan: plan)
    }

    /// `optionId` is a `TTSEngine.rawValue`.
    func tts(optionId raw: String) -> ModelLaneReadiness {
        ttsState(optionId: raw).readiness
    }

    func ttsState(optionId raw: String) -> ModelLaneState {
        guard let engine = TTSEngine(rawValue: raw) else {
            return ModelLaneState(readiness: .cloudUnconfigured, reason: .invalidRoute)
        }
        guard let providerId = engine.providerID else {
            return ttsLocalInstalled() ? .localReady : .localMissing
        }
        return cloud(.tts, providerId: providerId)
    }

    /// `optionId` is an `OCREngine.rawValue`. OCR isn't routed through `ProviderConfigDispatcher`,
    /// so its keys are read from `OCRCredentialAccount` directly.
    func ocr(optionId raw: String) -> ModelLaneReadiness {
        ocrState(optionId: raw).readiness
    }

    func ocrState(optionId raw: String) -> ModelLaneState {
        guard let engine = OCREngine(rawValue: raw) else {
            return ModelLaneState(readiness: .cloudUnconfigured, reason: .invalidRoute)
        }
        switch engine {
        case .appleVision:
            return .localReady
        case .paddleOCRLocal:
            return ocrLocalInstalled() ? .localReady : .localMissing
        case .mistral:
            return nonEmpty(ocrKeyReader(OCRCredentialAccount.mistralAPIKey)) != nil
                ? ModelLaneState(readiness: .cloudReady, reason: .ready)
                : ModelLaneState(readiness: .cloudUnconfigured, reason: .missingCredential)
        case .baidu:
            // 百度 needs both an API key and a secret key for its two-step OAuth.
            let ready = nonEmpty(ocrKeyReader(OCRCredentialAccount.baiduAPIKey)) != nil
                && nonEmpty(ocrKeyReader(OCRCredentialAccount.baiduSecretKey)) != nil
            return ready
                ? ModelLaneState(readiness: .cloudReady, reason: .ready)
                : ModelLaneState(readiness: .cloudUnconfigured, reason: .missingCredential)
        }
    }

    func resolvedConfig(
        _ capability: ModelCapability,
        providerId: String,
        plan: BillingPlan? = nil
    ) -> ResolvedProviderConfig {
        plan.map { dispatcher.resolve(capability, providerId: providerId, plan: $0) }
            ?? dispatcher.resolve(capability, providerId: providerId)
    }

    func resolvedLLM(providerId: String, plan: BillingPlan? = nil) -> ResolvedLLMLanes {
        dispatcher.resolveLLM(providerId: providerId, plan: plan)
    }

    static func cloudState(for config: ResolvedProviderConfig) -> ModelLaneState {
        guard !config.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ModelLaneState(readiness: .cloudUnconfigured, reason: .missingModel)
        }
        guard let components = URLComponents(
            string: config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(),
              ["http", "https", "ws", "wss"].contains(scheme),
              components.host != nil
        else {
            return ModelLaneState(readiness: .cloudUnconfigured, reason: .invalidEndpoint)
        }
        guard config.hasKey else {
            return ModelLaneState(readiness: .cloudUnconfigured, reason: .missingCredential)
        }
        return ModelLaneState(readiness: .cloudReady, reason: .ready)
    }

    private func cloud(
        _ capability: ModelCapability,
        providerId: String,
        plan: BillingPlan? = nil
    ) -> ModelLaneState {
        guard ProviderCatalog.presets(for: capability).contains(where: { $0.id == providerId }) else {
            return ModelLaneState(readiness: .cloudUnconfigured, reason: .invalidRoute)
        }
        return Self.cloudState(for: resolvedConfig(capability, providerId: providerId, plan: plan))
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
