import Foundation
import ResponsayCore

/// 233 — the BYOK consumer `ModelsKeysPane` was missing.
///
/// The capability cards persist a per-capability selection (`byok.<cap>.provider/region/
/// plan/model/voice/baseURL` in `UserDefaults`, key in `BYOKKeychain` under the account
/// selected by `CapabilityCredentialAccount`)
/// but nothing read it back, so a key typed there never reached the backend (the orphan-keys
/// gap in issue 222). `ProviderConfigDispatcher` resolves that selection into one concrete
/// `ResolvedProviderConfig` per request type (ASR / LLM / TTS), falling back to
/// `ProviderCatalog` defaults so an untouched install still resolves. It is pure given its
/// injected `defaults` + `keyReader`, so it unit-tests without the real Keychain.
struct ResolvedProviderConfig: Equatable, Sendable {
    let capability: ModelCapability
    let providerId: String
    let region: ProviderRegion
    let plan: BillingPlan
    let baseURL: String
    let model: String
    let voice: String?
    let workspaceID: String?
    let apiKey: String?
    let appId: String?
    let accessToken: String?

    var hasKey: Bool { !(apiKey ?? "").isEmpty || (!(appId ?? "").isEmpty && !(accessToken ?? "").isEmpty) }
}

/// One effective snapshot for the two LLM lanes. Provider routing and credentials are resolved
/// once; the skill lane may only replace the model within that same snapshot.
struct ResolvedLLMLanes: Equatable, Sendable {
    let provider: ResolvedProviderConfig
    let dictationEndpoint: LLMEndpoint
    let skillEndpoint: LLMEndpoint
    let explicitSkillModel: String?

    var skillFollowsDictation: Bool { explicitSkillModel == nil }
}

struct ProviderConfigDispatcher {
    private let defaults: UserDefaults
    /// account (e.g. `"byok.qwen"` or `"byok.tts.qwen"`) → key.
    /// Injected; production reads the Keychain.
    private let keyReader: (String) -> String?

    init(
        defaults: UserDefaults = .standard,
        keyReader: @escaping (String) -> String? = { BYOKKeychain.read($0) }
    ) {
        self.defaults = defaults
        self.keyReader = keyReader
    }

    /// Resolve the user's selection for one capability into a concrete config. Reads the same
    /// `byok.<cap>.<field>` keys the settings machine persists; any unset field falls back
    /// to the catalog default for the resolved provider (the same precedence the pane uses on
    /// first load).
    func resolve(_ capability: ModelCapability) -> ResolvedProviderConfig {
        resolve(capability, providerIdOverride: nil)
    }

    func resolve(_ capability: ModelCapability, providerId providerIdOverride: String) -> ResolvedProviderConfig {
        resolve(capability, providerIdOverride: providerIdOverride)
    }

    /// Resolve with an explicit billing plan — used by readiness to check a specific plan's key
    /// regardless of the currently-stored plan.
    func resolve(_ capability: ModelCapability, providerId providerIdOverride: String, plan: BillingPlan) -> ResolvedProviderConfig {
        resolve(capability, providerIdOverride: providerIdOverride, planOverride: plan)
    }

    /// Resolve both LLM lanes from one provider snapshot. The skill override is provider-scoped;
    /// an obsolete active mirror can therefore never contribute a foreign provider's model.
    func resolveLLM(providerId: String? = nil, plan: BillingPlan? = nil) -> ResolvedLLMLanes {
        let provider: ResolvedProviderConfig
        if let providerId, let plan {
            provider = resolve(.llm, providerId: providerId, plan: plan)
        } else if let providerId {
            provider = resolve(.llm, providerId: providerId)
        } else if let plan {
            let active = resolve(.llm)
            provider = resolve(.llm, providerId: active.providerId, plan: plan)
        } else {
            provider = resolve(.llm)
        }
        let explicitSkillModel = SkillPlatformModelSettings.explicitModel(
            providerId: provider.providerId,
            defaults: defaults)
        let dictationEndpoint = llmEndpoint(provider: provider, model: provider.model)
        let skillEndpoint = llmEndpoint(
            provider: provider,
            model: explicitSkillModel ?? provider.model)
        return ResolvedLLMLanes(
            provider: provider,
            dictationEndpoint: dictationEndpoint,
            skillEndpoint: skillEndpoint,
            explicitSkillModel: explicitSkillModel)
    }

    private func resolve(_ capability: ModelCapability, providerIdOverride: String?, planOverride: BillingPlan? = nil) -> ResolvedProviderConfig {
        let presets = ProviderCatalog.presets(for: capability)
        func activeField(_ suffix: String) -> String {
            CapabilityProviderConfigStore.activeKey(suffix, capability: capability)
        }

        let storedProviderId = nonEmpty(defaults.string(forKey: activeField("provider")))
        var providerId = Self.canonicalProviderId(providerIdOverride ?? storedProviderId ?? Self.defaultProviderId(presets))
        if !presets.contains(where: { $0.id == providerId }) {
            providerId = Self.defaultProviderId(presets)
        }
        let preset = presets.first { $0.id == providerId } ?? presets.first ?? ProviderCatalog.custom
        let storedRegion = CapabilityProviderConfigStore.string(
            "region", providerId: providerId, capability: capability, defaults: defaults, activeProviderId: storedProviderId)
        let storedPlan = CapabilityProviderConfigStore.string(
            "plan", providerId: providerId, capability: capability, defaults: defaults, activeProviderId: storedProviderId)
        let storedModel = CapabilityProviderConfigStore.string(
            "model", providerId: providerId, capability: capability, defaults: defaults, activeProviderId: storedProviderId)
        let storedVoice = CapabilityProviderConfigStore.string(
            "voice", providerId: providerId, capability: capability, defaults: defaults, activeProviderId: storedProviderId)
        let storedBaseURL = CapabilityProviderConfigStore.string(
            "baseURL", providerId: providerId, capability: capability, defaults: defaults, activeProviderId: storedProviderId)
        let storedWorkspaceID = CapabilityProviderConfigStore.string(
            "workspaceId", providerId: providerId, capability: capability,
            defaults: defaults, activeProviderId: storedProviderId)

        let variants = preset.endpoints(for: capability)
        let availableRegions = preset.regions(for: capability)
        let requestedRegion = ProviderRegion(rawValue: storedRegion ?? "")
        let storedRegionSelection = requestedRegion.flatMap { availableRegions.contains($0) ? $0 : nil }
        let initialRegion = storedRegionSelection
            ?? availableRegions.first ?? .global
        let storedPlanSelection = MiMoASRRouting.normalizedPlan(
            providerId: providerId,
            capability: capability,
            stored: BillingPlan(rawValue: storedPlan ?? ""),
            fallback: preset.plans(for: capability).first ?? .payg)
        let initialPlan = planOverride ?? storedPlanSelection
        let planOverrideChangedStoredSelection = planOverride.map { $0 != storedPlanSelection } ?? false
        let availablePlans = preset.plans(for: capability)
        let requestedPlanIsUnavailable = !availablePlans.contains(initialPlan)
        let availablePlan = availablePlans.contains(initialPlan)
            ? initialPlan
            : (availablePlans.first ?? .payg)
        // Region and plan form one endpoint selection, not independent axes. In particular,
        // MiMo PAYG exists only in China; a persisted Singapore + PAYG combination must resolve
        // to China PAYG instead of pairing a Singapore Token Plan host with the PAYG credential.
        let selectedVariant = variants.first { $0.region == initialRegion && $0.plan == availablePlan }
            ?? variants.first { $0.plan == availablePlan }
            ?? variants.first
        let region = selectedVariant?.region ?? initialRegion
        let plan = selectedVariant?.plan ?? availablePlan
        let routePairWasNormalized = region != initialRegion || plan != availablePlan
        let storedRegionWasUnavailable = nonEmpty(storedRegion) != nil && storedRegionSelection == nil
        // 千问非实时 ASR: the model is user-selectable (Qwen-Audio-3.0-ASR-Flash / Fun-ASR-Flash),
        // but a stored `…-realtime-…` id left by the retired OmniRealtime engine must not be sent.
        let isQwenASRFlash = capability == .asr && providerId == QwenASRFlashRouting.providerId
        let fixedQwenAudioTTS = capability == .tts && providerId == "qwen"
        let fixedProviderSurface = fixedQwenAudioTTS
        let catalogModel = preset.defaultModel(for: capability, plan: plan) ?? ""
        let model: String
        if fixedProviderSurface {
            model = catalogModel
        } else if isQwenASRFlash {
            model = QwenASRFlashRouting.normalizedModel(stored: storedModel, fallback: catalogModel)
        } else {
            model = nonEmpty(storedModel) ?? catalogModel
        }
        let voice = resolvedVoice(
            capability: capability,
            providerId: providerId,
            preset: preset,
            storedVoice: storedVoice)
        let catalogBaseURL = selectedVariant?.baseURL
            ?? preset.endpoint(for: capability, region: region, plan: plan)?.baseURL
            ?? ""
        let normalizedBaseURL = MiMoASRRouting.normalizedBaseURL(
            providerId: providerId,
            capability: capability,
            stored: storedBaseURL,
            fallback: catalogBaseURL)
        let selectedBaseURL = fixedProviderSurface || requestedPlanIsUnavailable
            || planOverrideChangedStoredSelection
            || routePairWasNormalized || storedRegionWasUnavailable
            ? catalogBaseURL
            : normalizedBaseURL
        let workspaceID: String?
        if isQwenASRFlash {
            workspaceID = QwenRunTaskEndpoint.normalizedWorkspaceID(storedWorkspaceID)
        } else if capability == .llm && providerId == "qwen" {
            workspaceID = nonEmpty(storedWorkspaceID).flatMap(QwenWorkspaceEndpoint.normalizedWorkspaceID)
        } else {
            workspaceID = nonEmpty(storedWorkspaceID)
        }
        let baseURL: String
        if isQwenASRFlash {
            // Fully derived from 接入点 + Workspace ID — the run-task path is fixed, so a stored
            // value (including anything the retired OmniRealtime engine left) contributes nothing.
            baseURL = QwenASRFlashRouting.displayBaseURL(workspaceID: workspaceID, region: region)
        } else if capability == .llm && providerId == "qwen" {
            baseURL = QwenWorkspaceEndpoint.baseURL(
                workspaceID: workspaceID ?? "", region: region) ?? selectedBaseURL
        } else {
            baseURL = selectedBaseURL
        }
        // Read only the credential shape this preset accepts. Besides avoiding irrelevant
        // Keychain work on latency-sensitive request paths, this prevents stale secret slots from
        // making a provider appear configured through a credential form its UI does not expose.
        let apiKey: String?
        let appId: String?
        let accessToken: String?
        if preset.isLocal {
            apiKey = nil
            appId = nil
            accessToken = nil
        } else {
            switch preset.credentialShape {
            case .apiKey:
                apiKey = apiKeyForProvider(
                    providerId: providerId,
                    capability: capability,
                    plan: plan)
                appId = nil
                accessToken = nil
            case .appIdAndToken:
                apiKey = nil
                appId = nonEmpty(keyReader(
                    CapabilityCredentialAccount.appIdAccount(providerId: providerId)))
                accessToken = nonEmpty(keyReader(
                    CapabilityCredentialAccount.accessTokenAccount(providerId: providerId)))
            }
        }

        return ResolvedProviderConfig(
            capability: capability, providerId: providerId, region: region, plan: plan,
            baseURL: baseURL, model: model, voice: voice, workspaceID: workspaceID,
            apiKey: apiKey, appId: appId, accessToken: accessToken)
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private func apiKeyForProvider(
        providerId: String,
        capability: ModelCapability,
        plan: BillingPlan
    ) -> String? {
        let account = CapabilityCredentialAccount.apiKeyAccount(
            providerId: providerId, capability: capability, plan: plan)
        return nonEmpty(keyReader(account))
    }

    private func llmEndpoint(provider: ResolvedProviderConfig, model: String) -> LLMEndpoint {
        LLMEndpoint(
            providerId: provider.providerId,
            baseURL: provider.baseURL,
            model: model,
            apiKey: provider.apiKey,
            thinkingEnabled: false)
    }

    /// TTS voice policy belongs to the effective configuration, not to individual UI/runtime
    /// callers. Qwen exposes a closed versioned roster, so retired values fall back; other
    /// providers deliberately accept non-empty custom/clone voice identifiers.
    private func resolvedVoice(
        capability: ModelCapability,
        providerId: String,
        preset: ProviderPreset,
        storedVoice: String?
    ) -> String? {
        guard capability == .tts else { return nil }
        let catalog = TTSProviderCatalogPresets.catalog(for: providerId)
        let fallback = catalog?.defaults.voiceID ?? preset.presetVoices.first?.id
        guard let voice = nonEmpty(storedVoice) else { return fallback }
        guard providerId == "qwen" else { return voice }
        return catalog?.voices.contains(where: { $0.id == voice }) == true ? voice : fallback
    }

    private static func defaultProviderId(_ presets: [ProviderPreset]) -> String {
        if presets.contains(where: { $0.id == "qwen" }) { return "qwen" }
        return presets.first?.id ?? "custom"
    }

    /// Map retained merged-provider aliases onto their surviving base provider so a stale
    /// stored selection resolves instead of silently falling back to the global default.
    private static func canonicalProviderId(_ providerId: String) -> String {
        switch providerId {
        case "qwen-team": return "qwen"
        case "mimo-payg": return "mimo"
        default: return providerId
        }
    }
}
