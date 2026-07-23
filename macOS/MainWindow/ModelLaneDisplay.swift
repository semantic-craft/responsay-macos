import Foundation
import ResponsayCore

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
    let modelId: String
    let isLocal: Bool
    let readiness: ModelLaneReadiness
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
        return ModelLaneInfo(
            lane: .asr,
            title: "语音识别",
            systemImage: "waveform",
            currentOptionId: id,
            currentTitle: engine.title,
            modelId: asrModelId(engine),
            isLocal: engine.associatedProviderId == nil,
            readiness: readiness.asr(optionId: id),
            settingsSection: .asr)
    }

    private func asrModelId(_ engine: ASREngine) -> String {
        guard let providerId = engine.associatedProviderId else {
            switch engine {
            case .sensevoiceLocal: return LocalModelSpec.senseVoiceSmall.id
            case .qwen3LocalASR: return LocalModelSpec.qwen3ASR.id
            case .fireRedASR2AEDLocal: return LocalModelSpec.fireRedASR2AED.id
            case .funAsrNanoLocal: return LocalModelSpec.funAsrNano.id
            default: return engine.rawValue
            }
        }
        return configuredModel(
            capability: .asr, providerId: providerId,
            storedProvider: defaults.string(forKey: "byok.asr.provider") ?? "",
            storedModel: defaults.string(forKey: "byok.asr.model") ?? "")
    }

    // MARK: - LLM

    private func llm() -> ModelLaneInfo {
        let id = Self.currentOptionId(for: .llm, defaults: defaults)
        // `id` may be plan-tagged ("mimo#package"); resolve the preset + model from the base,
        // mirroring ModelLaneReadinessResolver.llm — otherwise the "#plan" suffix fails the
        // preset lookup and the model id falls back to the literal "默认模型".
        let (base, _) = ModelRouteOptionID.parse(id)
        let preset = ProviderCatalog.presets(for: .llm).first { $0.id == base }
        return ModelLaneInfo(
            lane: .llm, title: "文本改写", systemImage: "sparkles",
            currentOptionId: id,
            currentTitle: preset?.displayName(for: .llm) ?? "自定义 OpenAI 兼容",
            modelId: configuredModel(
                capability: .llm, providerId: base,
                storedProvider: defaults.string(forKey: "byok.llm.provider") ?? "",
                storedModel: defaults.string(forKey: "byok.llm.model") ?? ""),
            isLocal: false,
            readiness: readiness.llm(optionId: id), settingsSection: .llm)
    }

    // MARK: - TTS

    private func tts() -> ModelLaneInfo {
        let id = Self.currentOptionId(for: .tts, defaults: defaults)
        let engine = TTSEngine(rawValue: id) ?? .sherpaKokoroLocal
        let modelId: String
        if let providerId = engine.providerID {
            modelId = configuredModel(
                capability: .tts, providerId: providerId,
                storedProvider: defaults.string(forKey: "byok.tts.provider") ?? "",
                storedModel: defaults.string(forKey: "byok.tts.model") ?? "")
        } else {
            modelId = LocalModelSpec.kokoroMultiLangV1_1.id
        }
        return ModelLaneInfo(
            lane: .tts, title: "文本朗读", systemImage: "speaker.wave.2",
            currentOptionId: id, currentTitle: engine.title,
            modelId: modelId, isLocal: engine.isLocal,
            readiness: readiness.tts(optionId: id), settingsSection: .tts)
    }

    // MARK: - OCR

    private func ocr() -> ModelLaneInfo {
        let id = Self.currentOptionId(for: .ocr, defaults: defaults)
        let engine = OCREngine(rawValue: id) ?? .appleVision
        return ModelLaneInfo(
            lane: .ocr, title: "图片识别", systemImage: "text.viewfinder",
            currentOptionId: id, currentTitle: engine.title,
            modelId: engine.modelLabel, isLocal: engine.isLocal,
            readiness: readiness.ocr(optionId: id), settingsSection: .ocr)
    }

    // MARK: - Shared

    /// The configured model id for a cloud lane: the user's stored model if it targets the
    /// selected provider, else that provider's catalog default. Mirrors the old
    /// `ModelRouteSelectionSection.configuredModel`.
    private func configuredModel(
        capability: ModelCapability, providerId: String,
        storedProvider: String, storedModel: String
    ) -> String {
        if CapabilitySelectionSync.providerMatches(storedProvider, providerId, capability: capability),
           let model = nonEmpty(storedModel) {
            return model
        }
        return ProviderCatalog.presets(for: capability)
            .first { CapabilitySelectionSync.providerMatches($0.id, providerId, capability: capability) }?
            .defaultModels[capability] ?? "默认模型"
    }

    private func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
