import Foundation
import ResponsayCore

extension Notification.Name {
    /// Content-free invalidation: consumers re-read the effective snapshot off the main thread.
    static let modelConfigurationDidChange = Notification.Name("ModelConfigurationDidChange")
}

enum ModelConfigurationEvents {
    static func post() {
        NotificationCenter.default.post(name: .modelConfigurationDidChange, object: nil)
    }
}

/// Display snapshot of one model lane (ASR / LLM / TTS / OCR): the current selection,
/// its resolved model id, whether it's local, its readiness, and the settings section
/// that configures it. The single source for the 设置·模型 panel (378) and the overview
/// status strip (382) — both render from `ModelLaneDisplay.lanes()`, so they never drift.
/// Pure given an injected `UserDefaults` + readiness resolver, so it unit-tests without
/// the real Keychain.
struct ModelLaneInfo: Identifiable, Equatable, Sendable {
    enum Lane: String, Sendable { case asr, llm, tts, ocr }

    let lane: Lane
    let title: String
    let systemImage: String
    let currentOptionId: String
    let currentTitle: String
    let providerId: String
    let plan: BillingPlan?
    let modelId: String
    let isLocal: Bool
    let readiness: ModelLaneReadiness
    let readinessReason: ModelLaneReadinessReason
    let settingsSection: SettingsSection

    var id: String { lane.rawValue }

    /// `本机` for on-device engines, `云端` for hosted ones.
    var badge: String { isLocal ? "本机" : "云端" }
}

struct ModelLaneDisplay {
    private let defaults: UserDefaults
    private let readiness: ModelLaneReadinessResolver

    init(
        defaults: UserDefaults = .standard,
        readiness: ModelLaneReadinessResolver = ModelLaneReadinessResolver()
    ) {
        self.defaults = defaults
        self.readiness = readiness
    }

    func lanes() -> [ModelLaneInfo] { [asr(), llm(), tts(), ocr()] }

    static func providerStatusSummary(from lanes: [ModelLaneInfo]) -> ProviderStatusSummary {
        func status(_ lane: ModelLaneInfo.Lane) -> ProviderStatus {
            guard let snapshot = lanes.first(where: { $0.lane == lane }) else { return .unknown }
            return .from(isConfigured: snapshot.readiness.isReady, isHealthy: true)
        }
        return ProviderStatusSummary(asr: status(.asr), llm: status(.llm), tts: status(.tts))
    }

    /// The current selection id for a lane, read cheaply from `UserDefaults` only — no Keychain,
    /// no readiness. Single definition of "which option is selected per lane": every lane builder
    /// below uses it for `currentOptionId`, and the 设置·模型 picker reads it directly so selection
    /// is instant without waiting on the Keychain-backed readiness recompute.
    static func currentOptionId(for lane: ModelLaneInfo.Lane, defaults: UserDefaults = .standard) -> String {
        switch lane {
        case .asr: return ModelRouteCatalog.currentASRId(defaults: defaults)
        case .llm: return ModelRouteCatalog.currentLLMId(defaults: defaults)
        case .tts: return ModelRouteCatalog.currentTTSId(defaults: defaults)
        case .ocr: return OCREngine.selected(defaults: defaults).rawValue
        }
    }

    // MARK: - ASR

    private func asr() -> ModelLaneInfo {
        let id = Self.currentOptionId(for: .asr, defaults: defaults)
        // `id` may be plan-tagged ("cloud-mimo#package"); resolve the engine from the base,
        // mirroring ModelLaneReadinessResolver.asr — otherwise the "#plan" suffix makes
        // fromStoredValue return nil and the lane wrongly falls back to local Apple
        // (showing 模型 ID "apple" / 本机 for a selected cloud MiMo engine).
        let (base, _) = ModelRouteOptionID.parse(id)
        let engine = ASREngine.fromStoredValue(base) ?? .apple
        let (_, plan) = ModelRouteOptionID.parse(id)
        let state = readiness.asrState(optionId: id)
        let config = engine.associatedProviderId.map {
            readiness.resolvedConfig(.asr, providerId: $0, plan: plan)
        }
        return ModelLaneInfo(
            lane: .asr,
            title: "语音识别",
            systemImage: "waveform",
            currentOptionId: id,
            currentTitle: engine.title,
            providerId: config?.providerId ?? engine.rawValue,
            plan: meaningfulPlan(config),
            modelId: config?.model ?? asrModelId(engine),
            isLocal: engine.associatedProviderId == nil,
            readiness: state.readiness,
            readinessReason: state.reason,
            settingsSection: .asr)
    }

    private func asrModelId(_ engine: ASREngine) -> String {
        switch engine {
        case .sensevoiceLocal: return LocalModelSpec.senseVoiceSmall.id
        case .qwen3LocalASR: return LocalModelSpec.qwen3ASR.id
        case .fireRedASR2AEDLocal: return LocalModelSpec.fireRedASR2AED.id
        case .funAsrNanoLocal: return LocalModelSpec.funAsrNano.id
        default: return engine.rawValue
        }
    }

    // MARK: - LLM

    private func llm() -> ModelLaneInfo {
        let id = Self.currentOptionId(for: .llm, defaults: defaults)
        // `id` may be plan-tagged ("mimo#package"); resolve the preset + model from the base,
        // mirroring ModelLaneReadinessResolver.llm — otherwise the "#plan" suffix fails the
        // preset lookup and the model id falls back to the literal "默认模型".
        let (base, _) = ModelRouteOptionID.parse(id)
        let (_, plan) = ModelRouteOptionID.parse(id)
        let lanes = readiness.resolvedLLM(providerId: base, plan: plan)
        let config = lanes.provider
        let preset = ProviderCatalog.presets(for: .llm).first { $0.id == config.providerId }
        let state = readiness.llmState(optionId: id)
        // 技能平台模型显式分流时快照要能区分两个选择；跟随时保持单模型显示不变。
        let skillModel = lanes.explicitSkillModel
        let modelId = (lanes.skillFollowsDictation || skillModel == config.model)
            ? config.model
            : "\(config.model) · 技能 \(skillModel!)"
        return ModelLaneInfo(
            lane: .llm, title: "文本改写", systemImage: "sparkles",
            currentOptionId: id,
            currentTitle: preset?.displayName(for: .llm) ?? "自定义 OpenAI 兼容",
            providerId: config.providerId,
            plan: meaningfulPlan(config),
            modelId: modelId,
            isLocal: false,
            readiness: state.readiness,
            readinessReason: state.reason,
            settingsSection: .llm)
    }

    // MARK: - TTS

    private func tts() -> ModelLaneInfo {
        let id = Self.currentOptionId(for: .tts, defaults: defaults)
        let engine = TTSEngine(rawValue: id) ?? .sherpaKokoroLocal
        let config = engine.providerID.map { readiness.resolvedConfig(.tts, providerId: $0) }
        let state = readiness.ttsState(optionId: id)
        return ModelLaneInfo(
            lane: .tts, title: "文本朗读", systemImage: "speaker.wave.2",
            currentOptionId: id, currentTitle: engine.title,
            providerId: config?.providerId ?? engine.rawValue,
            plan: meaningfulPlan(config),
            modelId: config?.model ?? LocalModelSpec.kokoroMultiLangV1_1.id,
            isLocal: engine.isLocal,
            readiness: state.readiness,
            readinessReason: state.reason,
            settingsSection: .tts)
    }

    // MARK: - OCR

    private func ocr() -> ModelLaneInfo {
        let id = Self.currentOptionId(for: .ocr, defaults: defaults)
        let engine = OCREngine(rawValue: id) ?? .appleVision
        let state = readiness.ocrState(optionId: id)
        return ModelLaneInfo(
            lane: .ocr, title: "图片识别", systemImage: "text.viewfinder",
            currentOptionId: id, currentTitle: engine.title,
            providerId: engine.rawValue,
            plan: nil,
            modelId: engine.modelLabel, isLocal: engine.isLocal,
            readiness: state.readiness,
            readinessReason: state.reason,
            settingsSection: .ocr)
    }

    // MARK: - Shared

    private func meaningfulPlan(_ config: ResolvedProviderConfig?) -> BillingPlan? {
        guard let config,
              ProviderCatalog.providerHasMultipleBillingPlans(
                config.providerId, capability: config.capability)
        else { return nil }
        return config.plan
    }
}
