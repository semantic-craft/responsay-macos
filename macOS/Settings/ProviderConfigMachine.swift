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
/// same `MiMoASRRouting` normalization and same fixed-endpoint forcing for the two 实时流式 ASR
/// engines (千问极速实时 / 豆包流式).
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
    var voice = ""
    var baseURL = ""
    var apiKey = ""
    var appId = ""
    var accessToken = ""
    var boostingTableId = ""
    var status = ""
    var fetchedModels: [String] = []
    var thinking = false

    @ObservationIgnored private var loaded = false
    @ObservationIgnored let defaults: UserDefaults

    init(capability: ModelCapability, preferredProviderId: String?, defaults: UserDefaults = .standard) {
        self.capability = capability
        self.preferredProviderId = preferredProviderId
        self.defaults = defaults
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

    /// The two 实时流式 ASR engines (千问极速实时 / 豆包流式) hardcode their WSS endpoint + model
    /// in code (QwenRealtimeEndpoint / VolcengineRealtimeEndpoint) and ignore the card's Base URL /
    /// 模型 ID. Show those fields read-only for them so the card can't display a stale batch config.
    var isFixedEndpoint: Bool {
        capability == .asr && (providerId == "qwen-asr-flash" || providerId == "volcengine-flash")
    }

    var currentRegions: [ProviderRegion] { current.regions(for: capability) }
    var currentPlans: [BillingPlan] { current.plans(for: capability) }
    var region: ProviderRegion { ProviderRegion(rawValue: regionRaw) ?? currentRegions.first ?? .global }
    var plan: BillingPlan { BillingPlan(rawValue: planRaw) ?? currentPlans.first ?? .payg }

    /// All non-empty endpoints (region × plan) for this capability, shown in one combined
    /// 「接入点」dropdown so 按量付费 / Token Plan sit next to 国内/新加坡/欧洲 instead of being
    /// separate providers (the Base URL below follows the pick).
    var endpointChoices: [EndpointVariant] {
        current.endpoints(for: capability).filter { !$0.baseURL.isEmpty }
    }

    // MARK: Keys

    func key(_ suffix: String) -> String { "byok.\(capability.rawValue).\(suffix)" }

    // MARK: Lifecycle

    func load() {
        guard !loaded else { return }
        loaded = true
        let d = defaults
        let storedProvider = d.string(forKey: key("provider"))
        var pid = preferredProviderId ?? storedProvider ?? defaultProviderId()
        if !presets.contains(where: { $0.id == pid }) { pid = defaultProviderId() }
        let prov = presets.first { $0.id == pid } ?? presets.first ?? ProviderCatalog.custom
        providerId = pid
        let defaultRegion = prov.regions(for: capability).first?.rawValue ?? ProviderRegion.global.rawValue
        let defaultPlan = prov.plans(for: capability).first?.rawValue ?? BillingPlan.payg.rawValue
        regionRaw = scopedString("region", providerId: pid, activeProviderId: storedProvider) ?? defaultRegion
        planRaw = MiMoASRRouting.normalizedPlanRaw(providerId: pid, capability: capability,
                                                   storedRaw: scopedString("plan", providerId: pid, activeProviderId: storedProvider),
                                                   fallbackRaw: defaultPlan)
        model = scopedString("model", providerId: pid, activeProviderId: storedProvider)
            ?? (prov.defaultModel(for: capability, plan: BillingPlan(rawValue: planRaw) ?? .payg) ?? "")
        let defaultVoice = prov.presetVoices.first?.id ?? ""
        voice = scopedString("voice", providerId: pid, activeProviderId: storedProvider) ?? defaultVoice
        let r = ProviderRegion(rawValue: regionRaw) ?? .global
        let pl = BillingPlan(rawValue: planRaw) ?? .payg
        baseURL = MiMoASRRouting.normalizedBaseURL(
            providerId: pid, capability: capability,
            stored: scopedString("baseURL", providerId: pid, activeProviderId: storedProvider),
            fallback: prov.endpoint(for: capability, region: r, plan: pl)?.baseURL ?? "")
        let shouldPersist = MiMoASRRouting.shouldPersistNormalizedDefaults(providerId: pid, capability: capability)
        if CapabilitySelectionSync.providerMatches(storedProvider, pid, capability: capability), shouldPersist {
            setScoped(planRaw, suffix: "plan")
            setScoped(baseURL, suffix: "baseURL")
            setScoped(voice, suffix: "voice")
        }
        // Fixed WSS engines (千问极速实时 / 豆包流式): force the true endpoint + model regardless of any
        // stale stored batch config, and persist so ModelLaneDisplay shows the realtime values too.
        if capability == .asr, pid == "qwen-asr-flash" || pid == "volcengine-flash" {
            baseURL = prov.endpoint(for: capability, region: r, plan: pl)?.baseURL ?? baseURL
            model = prov.defaultModel(for: capability, plan: pl) ?? model
            setScoped(baseURL, suffix: "baseURL")
            setScoped(model, suffix: "model")
        }
        apiKey = BYOKKeychain.read(
            CapabilityCredentialAccount.apiKeyAccount(
                providerId: pid, capability: capability, plan: BillingPlan(rawValue: planRaw) ?? .payg)) ?? ""
        appId = BYOKKeychain.read(CapabilityCredentialAccount.appIdAccount(providerId: pid)) ?? ""
        accessToken = BYOKKeychain.read(CapabilityCredentialAccount.accessTokenAccount(providerId: pid)) ?? ""
        boostingTableId = d.string(forKey: "byok.\(pid).boostingTableId") ?? ""
        thinking = CapabilityProviderConfigStore.bool(
            "thinking", providerId: pid, capability: capability, defaults: d, activeProviderId: storedProvider)
    }

    func defaultProviderId() -> String {
        if presets.contains(where: { $0.id == "qwen" }) { return "qwen" }
        return presets.first?.id ?? "custom"
    }

    func selectProvider() {
        let prov = current
        let activeProvider = defaults.string(forKey: key("provider"))
        let defaultRegion = prov.regions(for: capability).first?.rawValue ?? ProviderRegion.global.rawValue
        let defaultPlan = prov.plans(for: capability).first?.rawValue ?? BillingPlan.payg.rawValue
        regionRaw = scopedString("region", providerId: prov.id, activeProviderId: activeProvider) ?? defaultRegion
        planRaw = MiMoASRRouting.normalizedPlanRaw(providerId: prov.id, capability: capability,
                                                   storedRaw: scopedString("plan", providerId: prov.id, activeProviderId: activeProvider),
                                                   fallbackRaw: defaultPlan)
        model = scopedString("model", providerId: prov.id, activeProviderId: activeProvider)
            ?? (prov.defaultModel(for: capability, plan: BillingPlan(rawValue: planRaw) ?? .payg) ?? "")
        let defaultVoice = prov.presetVoices.first?.id ?? ""
        voice = scopedString("voice", providerId: prov.id, activeProviderId: activeProvider) ?? defaultVoice
        baseURL = prov.endpoint(for: capability, region: ProviderRegion(rawValue: regionRaw) ?? .global,
                                plan: BillingPlan(rawValue: planRaw) ?? .payg)?.baseURL ?? ""
        baseURL = MiMoASRRouting.normalizedBaseURL(
            providerId: prov.id, capability: capability,
            stored: scopedString("baseURL", providerId: prov.id, activeProviderId: activeProvider), fallback: baseURL)
        if capability == .asr, prov.id == "qwen-asr-flash" || prov.id == "volcengine-flash" {
            let pl = BillingPlan(rawValue: planRaw) ?? .payg
            baseURL = prov.endpoint(for: capability,
                                    region: ProviderRegion(rawValue: regionRaw) ?? .global, plan: pl)?.baseURL ?? baseURL
            model = prov.defaultModel(for: capability, plan: pl) ?? model
            setScoped(baseURL, suffix: "baseURL")
            setScoped(model, suffix: "model")
        }
        apiKey = BYOKKeychain.read(
            CapabilityCredentialAccount.apiKeyAccount(
                providerId: prov.id, capability: capability, plan: BillingPlan(rawValue: planRaw) ?? .payg)) ?? ""
        appId = BYOKKeychain.read(CapabilityCredentialAccount.appIdAccount(providerId: prov.id)) ?? ""
        accessToken = BYOKKeychain.read(CapabilityCredentialAccount.accessTokenAccount(providerId: prov.id)) ?? ""
        boostingTableId = defaults.string(forKey: "byok.\(prov.id).boostingTableId") ?? ""
        thinking = CapabilityProviderConfigStore.bool(
            "thinking", providerId: prov.id, capability: capability, defaults: defaults, activeProviderId: activeProvider)
        status = ""
        fetchedModels = []
    }

    func endpointBase() -> String {
        current.endpoint(for: capability, region: region, plan: plan)?.baseURL ?? baseURL
    }

    /// Load the API key stored for the current plan. 按量付费 and Token Plan keep separate keys
    /// (sk- vs tp-), so switching the 接入点 dropdown shows that plan's key (or blank) instead
    /// of carrying the other plan's key over and sending it to the wrong host → 401.
    func reloadKeyForCurrentPlan() {
        apiKey = BYOKKeychain.read(
            CapabilityCredentialAccount.apiKeyAccount(
                providerId: providerId, capability: capability, plan: plan)) ?? ""
    }

    /// When the billing plan changes and the user hasn't customized the model away from the old
    /// plan's default, retarget it to the new plan's default. No-op when both plans share a default
    /// (Qwen 按量付费/Token Plan 现都默认 qwen3.6-flash；MiMo → mimo-v2.5).
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
        setScoped(voice, suffix: "voice")
        setScoped(baseURL, suffix: "baseURL")
        setScoped(thinking, suffix: "thinking")
    }

    func scopedString(_ suffix: String, providerId pid: String, activeProviderId: String?) -> String? {
        CapabilityProviderConfigStore.string(
            suffix, providerId: pid, capability: capability, defaults: defaults, activeProviderId: activeProviderId)
    }

    func setScoped(_ value: Any, suffix: String) {
        CapabilityProviderConfigStore.set(
            value, suffix: suffix, providerId: providerId, capability: capability,
            defaults: defaults, activeProviderId: defaults.string(forKey: key("provider")))
    }

    // MARK: Credential writers (keychain — ADR-0023, never stored in UserDefaults/plaintext)

    func writeApiKey() {
        BYOKKeychain.write(
            apiKey,
            account: CapabilityCredentialAccount.apiKeyAccount(
                providerId: providerId, capability: capability, plan: plan))
    }

    func writeAppId() {
        BYOKKeychain.write(appId, account: CapabilityCredentialAccount.appIdAccount(providerId: providerId))
    }

    func writeAccessToken() {
        BYOKKeychain.write(
            accessToken,
            account: CapabilityCredentialAccount.accessTokenAccount(providerId: providerId))
    }

    func writeBoostingTableId() {
        defaults.set(
            boostingTableId.trimmingCharacters(in: .whitespacesAndNewlines),
            forKey: "byok.\(providerId).boostingTableId")
    }
}
