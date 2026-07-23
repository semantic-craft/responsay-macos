import Foundation
import ResponsayCore

/// Readiness of one model option (a menu choice or the current selection): local
/// engines are always ready (no key); cloud engines are ready iff a BYOK key exists.
/// Single source for the 设置·模型 panel pills (378), the menu-bar jump-to-config
/// decision (379), and the overview status strip (382) — the three surfaces never
/// drift on "configured or not".
enum ModelLaneReadiness: Equatable {
    /// On-device engine — no key, always usable.
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

/// Resolves the readiness of an ASR / LLM / TTS / OCR option. Pure given an injected
/// `ProviderConfigDispatcher` (which carries its own defaults + Keychain reader) and an
/// OCR key reader (OCR isn't a `ModelCapability`, so its keys live in `OCRCredentialAccount`),
/// so it unit-tests without the real Keychain. Mirrors `OverviewScreen.providerStatus`'s
/// `isLocal || hasKey` rule — zero new readiness logic, just per-option resolution.
struct ModelLaneReadinessResolver {
    private let dispatcher: ProviderConfigDispatcher
    private let ocrKeyReader: (String) -> String?
    private let ocrLocalInstalled: () -> Bool

    init(
        dispatcher: ProviderConfigDispatcher = ProviderConfigDispatcher(),
        ocrKeyReader: @escaping (String) -> String? = { BYOKKeychain.read($0) },
        ocrLocalInstalled: @escaping () -> Bool = { LocalModelRegistry.defaultOCR.isInstalled }
    ) {
        self.dispatcher = dispatcher
        self.ocrKeyReader = ocrKeyReader
        self.ocrLocalInstalled = ocrLocalInstalled
    }

    /// `optionId` is an `ASREngine.rawValue`, optionally plan-tagged (`cloud-mimo#package`).
    func asr(optionId raw: String) -> ModelLaneReadiness {
        let (base, plan) = ModelRouteOptionID.parse(raw)
        guard let engine = ASREngine.fromStoredValue(base),
              let providerId = engine.associatedProviderId else { return .local }
        return cloud(.asr, providerId: providerId, plan: plan)
    }

    /// `optionId` is an LLM provider id (optionally plan-tagged, `mimo#package`).
    func llm(optionId id: String) -> ModelLaneReadiness {
        let (base, plan) = ModelRouteOptionID.parse(id)
        return cloud(.llm, providerId: base, plan: plan)
    }

    /// `optionId` is a `TTSEngine.rawValue`.
    func tts(optionId raw: String) -> ModelLaneReadiness {
        guard let engine = TTSEngine(rawValue: raw),
              let providerId = engine.providerID else { return .local }
        return cloud(.tts, providerId: providerId)
    }

    /// `optionId` is an `OCREngine.rawValue`. OCR isn't routed through `ProviderConfigDispatcher`,
    /// so its keys are read from `OCRCredentialAccount` directly.
    func ocr(optionId raw: String) -> ModelLaneReadiness {
        guard let engine = OCREngine(rawValue: raw) else { return .local }
        switch engine {
        case .appleVision:
            return .local
        case .paddleOCRLocal:
            return ocrLocalInstalled() ? .local : .localNotInstalled
        case .mistral:
            return nonEmpty(ocrKeyReader(OCRCredentialAccount.mistralAPIKey)) != nil
                ? .cloudReady : .cloudUnconfigured
        case .baidu:
            // 百度 needs both an API key and a secret key for its two-step OAuth.
            let ready = nonEmpty(ocrKeyReader(OCRCredentialAccount.baiduAPIKey)) != nil
                && nonEmpty(ocrKeyReader(OCRCredentialAccount.baiduSecretKey)) != nil
            return ready ? .cloudReady : .cloudUnconfigured
        }
    }

    private func cloud(_ capability: ModelCapability, providerId: String, plan: BillingPlan? = nil) -> ModelLaneReadiness {
        let config = plan.map { dispatcher.resolve(capability, providerId: providerId, plan: $0) }
            ?? dispatcher.resolve(capability, providerId: providerId)
        return config.hasKey ? .cloudReady : .cloudUnconfigured
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
