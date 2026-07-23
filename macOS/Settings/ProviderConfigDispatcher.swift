import Foundation

/// 233 — the BYOK consumer `ModelsKeysPane` was missing.
///
/// The capability cards persist a per-capability selection (`byok.<cap>.provider/region/
/// plan/model/baseURL` in `UserDefaults`, key in `BYOKKeychain` under the account
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
    let apiKey: String?
    let appId: String?
    let accessToken: String?

    var hasKey: Bool { !(apiKey ?? "").isEmpty || (!(appId ?? "").isEmpty && !(accessToken ?? "").isEmpty) }
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
    /// `byok.<cap>.<field>` keys `ModelsKeysPane.persist()` writes; any unset field falls back
    /// to the catalog default for the resolved provider (the same precedence the pane uses on
    /// first load).
    func resolve(_ capability: ModelCapability) -> ResolvedProviderConfig {
        resolve(capability, providerIdOverride: nil)
    }

    func resolve(_ capability: ModelCapability, providerId providerIdOverride: String) -> ResolvedProviderConfig {
        resolve(capability, providerIdOverride: providerIdOverride)
    }

    /// Resolve with an explicit billing plan — used by readiness to check a specific plan's key
    /// (e.g. is the Token Plan slot configured?) regardless of the currently-stored plan.
    func resolve(_ capability: ModelCapability, providerId providerIdOverride: String, plan: BillingPlan) -> ResolvedProviderConfig {
        resolve(capability, providerIdOverride: providerIdOverride, planOverride: plan)
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
        let storedBaseURL = CapabilityProviderConfigStore.string(
            "baseURL", providerId: providerId, capability: capability, defaults: defaults, activeProviderId: storedProviderId)

        let region = ProviderRegion(rawValue: storedRegion ?? "")
            ?? preset.regions(for: capability).first ?? .global
        let plan = planOverride ?? MiMoASRRouting.normalizedPlan(
            providerId: providerId,
            capability: capability,
            stored: BillingPlan(rawValue: storedPlan ?? ""),
            fallback: preset.plans(for: capability).first ?? .payg)
        let fixedQwenRealtime = capability == .asr && providerId == "qwen-asr-flash"
        let fixedQwenAudioTTS = capability == .tts && providerId == "qwen"
        let fixedProviderSurface = fixedQwenRealtime || fixedQwenAudioTTS
        let model = fixedProviderSurface
            ? (preset.defaultModel(for: capability, plan: plan) ?? "")
            : (nonEmpty(storedModel) ?? preset.defaultModel(for: capability, plan: plan) ?? "")
        let catalogBaseURL = preset.endpoint(for: capability, region: region, plan: plan)?.baseURL ?? ""
        let baseURL = fixedProviderSurface
            ? catalogBaseURL
            : MiMoASRRouting.normalizedBaseURL(
                providerId: providerId,
                capability: capability,
                stored: storedBaseURL,
                fallback: catalogBaseURL)
        // Local engines have no key; never surface one even if a stale Keychain item exists.
        let apiKey = preset.isLocal ? nil : apiKeyForProvider(
            providerId: providerId,
            capability: capability,
            plan: plan)
        let appId = preset.isLocal
            ? nil
            : nonEmpty(keyReader(CapabilityCredentialAccount.appIdAccount(providerId: providerId)))
        let accessToken = preset.isLocal
            ? nil
            : nonEmpty(keyReader(CapabilityCredentialAccount.accessTokenAccount(providerId: providerId)))

        return ResolvedProviderConfig(
            capability: capability, providerId: providerId, region: region, plan: plan,
            baseURL: baseURL, model: model, apiKey: apiKey, appId: appId, accessToken: accessToken)
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
        let primaryAccount = CapabilityCredentialAccount.apiKeyAccount(
            providerId: providerId,
            capability: capability,
            plan: plan)
        if let primary = nonEmpty(keyReader(primaryAccount)) { return primary }

        return nil
    }

    private static func defaultProviderId(_ presets: [ProviderPreset]) -> String {
        if presets.contains(where: { $0.id == "qwen" }) { return "qwen" }
        return presets.first?.id ?? "custom"
    }

    /// Map retired/merged provider ids onto their surviving base provider so a stale
    /// stored selection resolves instead of silently falling back to the global default.
    /// Token Plan / 按量付费 are now billing plans inside `qwen` / `mimo`, not providers.
    private static func canonicalProviderId(_ providerId: String) -> String {
        switch providerId {
        case "qwen-team", "qwen-token-plan": return "qwen"
        case "mimo-payg": return "mimo"
        default: return providerId
        }
    }
}
