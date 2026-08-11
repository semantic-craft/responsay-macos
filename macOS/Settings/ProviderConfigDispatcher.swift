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

        let endpoints = preset.endpoints(for: capability)
        let availableRegions = preset.regions(for: capability)
        let requestedRegion = ProviderRegion(rawValue: storedRegion ?? "")
        let storedRegionSelection = requestedRegion.flatMap { availableRegions.contains($0) ? $0 : nil }
        let independentRegion = storedRegionSelection
            ?? availableRegions.first ?? .global
        let storedPlanSelection = MiMoASRRouting.normalizedPlan(
            providerId: providerId,
            capability: capability,
            stored: BillingPlan(rawValue: storedPlan ?? ""),
            fallback: preset.plans(for: capability).first ?? .payg)
        let requestedPlan = planOverride ?? storedPlanSelection
        let planOverrideChangedStoredSelection = planOverride.map { $0 != storedPlanSelection } ?? false
        let availablePlans = preset.plans(for: capability)
        let requestedPlanIsUnavailable = !availablePlans.contains(requestedPlan)
        let independentPlan = availablePlans.contains(requestedPlan)
            ? requestedPlan
            : (availablePlans.first ?? .payg)
        let endpoint: EndpointVariant?
        let region: ProviderRegion
        let plan: BillingPlan
        if capability == .asr {
            // ASR region + plan describe one endpoint choice, not two independent switches.
            // Prefer the requested tuple; if it is impossible (for example Singapore + MiMo
            // PAYG), keep the requested plan and choose a real endpoint that offers it. This
            // ensures the endpoint and plan-scoped credential cannot come from incompatible rows.
            endpoint = preset.effectiveASREndpoint(
                requestedRegion: requestedRegion,
                plan: requestedPlan)
            region = endpoint?.region ?? independentRegion
            plan = endpoint?.plan ?? independentPlan
        } else {
            // Region and plan describe one endpoint choice. If a stored tuple is impossible,
            // retain the requested plan and choose a real endpoint that offers it.
            endpoint = endpoints.first { $0.region == independentRegion && $0.plan == independentPlan }
                ?? endpoints.first { $0.plan == independentPlan }
                ?? endpoints.first
            region = endpoint?.region ?? independentRegion
            plan = endpoint?.plan ?? independentPlan
        }
        let routePairWasNormalized = region != independentRegion || plan != independentPlan
        let storedRegionWasUnavailable = nonEmpty(storedRegion) != nil && storedRegionSelection == nil
        // 千问非实时 ASR: the model is user-selectable (Qwen-Audio-3.0-ASR-Flash / Fun-ASR-Flash),
        // but a stored `…-realtime-…` id left by the retired OmniRealtime engine must not be sent.
        let isQwenASRFlash = capability == .asr && providerId == QwenASRFlashRouting.providerId
        // 豆包流式 owns its WSS protocol surface in `VolcengineRealtimeEndpoint`. Persisted values
        // are display mirrors only and must never replace that fixed endpoint/model at capture time.
        let fixedVolcengineASR = capability == .asr && providerId == "volcengine-flash"
        let fixedQwenAudioTTS = capability == .tts && providerId == "qwen"
        let fixedProviderSurface = fixedVolcengineASR || fixedQwenAudioTTS
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
        let catalogBaseURL = endpoint?.baseURL ?? ""
        let normalizedBaseURL = MiMoASRRouting.normalizedBaseURL(
            providerId: providerId,
            capability: capability,
            stored: storedBaseURL,
            fallback: catalogBaseURL)
        let selectedEndpointIdentity = endpointIdentity(catalogBaseURL)
        let storedEndpointIdentity = endpointIdentity(normalizedBaseURL)
        let knownEndpointIdentities = Set(endpoints.compactMap { endpointIdentity($0.baseURL) })
        let storedMiMoEndpointConflictsWithTuple = capability == .asr
            && providerId == "mimo"
            && storedEndpointIdentity != selectedEndpointIdentity
            && storedEndpointIdentity.map(knownEndpointIdentities.contains) == true
        let selectedBaseURL = fixedProviderSurface
            || requestedPlanIsUnavailable
            || planOverrideChangedStoredSelection
            || routePairWasNormalized
            || storedRegionWasUnavailable
            || storedMiMoEndpointConflictsWithTuple
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

    /// Comparison identity for catalog endpoints. Host/scheme case, default ports and trailing
    /// path slashes do not create a distinct route; query/fragment/user-info do, so they are kept
    /// outside the catalog match and cannot accidentally inherit a known endpoint's trust.
    private func endpointIdentity(_ raw: String) -> String? {
        guard let value = nonEmpty(raw),
              let components = URLComponents(string: value),
              let rawScheme = components.scheme,
              let rawHost = components.host,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            return nil
        }
        let scheme = rawScheme.lowercased()
        let host = rawHost.lowercased()
        let port = components.port.flatMap { value -> Int? in
            if (scheme == "http" && value == 80) || (scheme == "https" && value == 443) {
                return nil
            }
            return value
        }
        var path = components.percentEncodedPath
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        if path.isEmpty { path = "/" }
        return "\(scheme)://\(host)\(port.map { ":\($0)" } ?? "")\(path)"
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
