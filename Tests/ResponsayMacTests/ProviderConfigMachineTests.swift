import Testing
import Foundation
@testable import ResponsayMac
@testable import ResponsayCore

/// Unit coverage for the provider-config logic extracted out of `CapabilityCardView` into
/// `ProviderConfigMachine`. These drive the machine directly (no SwiftUI rendering), asserting
/// the deterministic plan→model routing, endpoint picking, `load()` seeding (incl. the two
/// fixed-endpoint 实时流式 ASR engines) and `endpointBase()` derivation.
///
/// Each test injects a fresh named `UserDefaults` suite so it's hermetic — no dependency on the
/// machine's `.standard` runtime store. BYOK keys live in the Keychain (ADR-0023) and read as
/// empty on a clean test host, so assertions pin only the UserDefaults-derived state, never keys.
@MainActor
struct ProviderConfigMachineTests {

    private func freshDefaults(_ suffix: String) -> UserDefaults {
        let name = "ProviderConfigMachineTests.\(suffix)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func machine(
        _ capability: ModelCapability,
        preferred: String? = nil,
        suffix: String
    ) -> ProviderConfigMachine {
        ProviderConfigMachine(
            capability: capability, preferredProviderId: preferred, defaults: freshDefaults(suffix))
    }

    // MARK: - load(): default provider seeding

    @Test func loadSeedsQwenLLMDefaultsFromEmptyStore() {
        let m = machine(.llm, suffix: "load-qwen-llm")
        m.load()
        #expect(m.providerId == "qwen")
        #expect(m.region == .china)
        #expect(m.plan == .payg)
        #expect(m.model == "qwen3.6-flash")
        #expect(m.baseURL == "https://dashscope.aliyuncs.com/compatible-mode/v1")
    }

    @Test func loadHonorsPreferredProviderId() {
        let m = machine(.llm, preferred: "openai", suffix: "load-preferred-openai")
        m.load()
        #expect(m.providerId == "openai")
        #expect(m.region == .global)
        #expect(m.plan == .payg)
        #expect(m.model == "chat-latest")
        #expect(m.baseURL == "https://api.openai.com/v1")
    }

    @Test func loadReadsStoredScopedConfig() {
        let d = freshDefaults("load-stored-scoped")
        d.set("openai", forKey: "byok.llm.provider")
        d.set("gpt-custom", forKey: "byok.llm.openai.model")
        let m = ProviderConfigMachine(capability: .llm, preferredProviderId: nil, defaults: d)
        m.load()
        #expect(m.providerId == "openai")
        #expect(m.model == "gpt-custom")
        #expect(m.baseURL == "https://api.openai.com/v1")
    }

    @Test func loadIsIdempotent() {
        let m = machine(.llm, suffix: "load-idempotent")
        m.load()
        m.model = "hand-edited"
        m.load()  // second call is a no-op; must not clobber
        #expect(m.model == "hand-edited")
    }

    // MARK: - load(): fixed-endpoint 实时流式 ASR engines

    @Test func loadForcesQwenRealtimeEndpointAndModel() {
        let m = machine(.asr, preferred: "qwen-asr-flash", suffix: "load-qwen-realtime")
        m.load()
        #expect(m.isFixedEndpoint)
        #expect(m.baseURL == "wss://dashscope.aliyuncs.com/api-ws/v1/realtime")
        #expect(m.model == QwenRealtimeEndpoint.defaultModel)
    }

    @Test func loadForcesVolcengineFlashEndpointAndModel() {
        let m = machine(.asr, preferred: "volcengine-flash", suffix: "load-volc-flash")
        m.load()
        #expect(m.isFixedEndpoint)
        #expect(m.baseURL == "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_nostream")
        #expect(m.model == "bigmodel")
    }

    @Test func loadForcesFixedEndpointEvenOverStaleStoredBatchConfig() {
        let d = freshDefaults("load-fixed-overrides-stale")
        d.set("qwen-asr-flash", forKey: "byok.asr.provider")
        // Stale batch config a user could have from before the realtime migration.
        d.set("https://stale.example.com/v1", forKey: "byok.asr.qwen-asr-flash.baseURL")
        d.set("stale-batch-model", forKey: "byok.asr.qwen-asr-flash.model")
        let m = ProviderConfigMachine(capability: .asr, preferredProviderId: nil, defaults: d)
        m.load()
        #expect(m.baseURL == "wss://dashscope.aliyuncs.com/api-ws/v1/realtime")
        #expect(m.model == QwenRealtimeEndpoint.defaultModel)
        // …and the forced values are persisted back so ModelLaneDisplay reflects them.
        #expect(d.string(forKey: "byok.asr.qwen-asr-flash.baseURL") == "wss://dashscope.aliyuncs.com/api-ws/v1/realtime")
        #expect(d.string(forKey: "byok.asr.qwen-asr-flash.model") == QwenRealtimeEndpoint.defaultModel)
    }

    // MARK: - selectProvider(): re-seeds state for the newly picked provider

    @Test func selectProviderReSeedsModelBaseURLRegionPlan() {
        let m = machine(.llm, suffix: "select-provider")
        m.load()
        #expect(m.providerId == "qwen")

        m.providerId = "openai"
        m.selectProvider()

        #expect(m.region == .global)
        #expect(m.plan == .payg)
        #expect(m.model == "chat-latest")
        #expect(m.baseURL == "https://api.openai.com/v1")
        #expect(m.status.isEmpty)
        #expect(m.fetchedModels.isEmpty)
    }

    @Test func selectProviderToMimoLLMPicksItsFirstEndpoint() {
        let m = machine(.llm, suffix: "select-mimo")
        m.load()
        m.providerId = "mimo"
        m.selectProvider()
        // MiMo LLM's first endpoint variant is (china, package).
        #expect(m.region == .china)
        #expect(m.plan == .package)
        #expect(m.model == "mimo-v2.5")
        #expect(m.baseURL == "https://token-plan-cn.xiaomimimo.com/v1")
    }

    // MARK: - endpointBase(): region × plan derivation

    @Test func endpointBaseFollowsRegionAndPlanForQwenLLM() {
        let m = machine(.llm, suffix: "endpoint-base")
        m.load()  // qwen · china · payg

        m.regionRaw = ProviderRegion.china.rawValue
        m.planRaw = BillingPlan.payg.rawValue
        #expect(m.endpointBase() == "https://dashscope.aliyuncs.com/compatible-mode/v1")

        m.planRaw = BillingPlan.package.rawValue
        #expect(m.endpointBase() == "https://token-plan.cn-beijing.maas.aliyuncs.com/compatible-mode/v1")

        m.regionRaw = ProviderRegion.singapore.rawValue
        m.planRaw = BillingPlan.payg.rawValue
        #expect(m.endpointBase() == "https://dashscope-intl.aliyuncs.com/compatible-mode/v1")
    }

    // MARK: - autoSwitchModel(): retarget only when uncustomized; no-op on shared default

    @Test func autoSwitchModelNoOpWhenPlansShareDefault() {
        // Qwen LLM: 按量付费 and Token Plan both default to qwen3.6-flash → switching plans must
        // NOT change a model the user set to that shared default.
        let m = machine(.llm, suffix: "autoswitch-shared")
        m.load()
        m.model = "qwen3.6-flash"
        m.autoSwitchModel(from: BillingPlan.payg.rawValue, to: BillingPlan.package.rawValue)
        #expect(m.model == "qwen3.6-flash")
    }

    @Test func autoSwitchModelLeavesCustomizedModelAloneOnSharedDefault() {
        // A model the user hand-edited away from the plan default is preserved: it neither equals
        // the old default nor is empty, so the retarget guard skips it.
        let m = machine(.llm, suffix: "autoswitch-custom")
        m.load()
        m.model = "qwen3.7-plus"
        m.autoSwitchModel(from: BillingPlan.payg.rawValue, to: BillingPlan.package.rawValue)
        #expect(m.model == "qwen3.7-plus")
    }

    @Test func autoSwitchModelNoOpWhenPlanUnchanged() {
        let m = machine(.llm, suffix: "autoswitch-same-plan")
        m.load()
        m.model = "hand-edited"
        m.autoSwitchModel(from: BillingPlan.payg.rawValue, to: BillingPlan.payg.rawValue)
        #expect(m.model == "hand-edited")
    }

    @Test func autoSwitchModelNoOpForUnknownPlanRaw() {
        let m = machine(.llm, suffix: "autoswitch-unknown")
        m.load()
        m.model = "hand-edited"
        m.autoSwitchModel(from: "not-a-plan", to: BillingPlan.package.rawValue)
        #expect(m.model == "hand-edited")
    }

    // MARK: - persist(): writes the scoped config set to the injected store

    @Test func persistWritesScopedConfigToInjectedDefaults() {
        let d = freshDefaults("persist-scoped")
        let m = ProviderConfigMachine(capability: .llm, preferredProviderId: nil, defaults: d)
        m.load()  // qwen
        m.model = "qwen3.7-plus"
        m.persist()
        #expect(d.string(forKey: "byok.llm.qwen.model") == "qwen3.7-plus")
        #expect(d.string(forKey: "byok.llm.qwen.region") == ProviderRegion.china.rawValue)
        #expect(d.string(forKey: "byok.llm.qwen.plan") == BillingPlan.payg.rawValue)
        #expect(d.string(forKey: "byok.llm.qwen.baseURL") == "https://dashscope.aliyuncs.com/compatible-mode/v1")
    }

    @Test func persistMirrorsToActiveKeyWhenProviderMatchesStored() {
        let d = freshDefaults("persist-active-mirror")
        d.set("qwen", forKey: "byok.llm.provider")
        let m = ProviderConfigMachine(capability: .llm, preferredProviderId: nil, defaults: d)
        m.load()
        m.model = "qwen3.6-plus"
        m.persist()
        // Active provider == the machine's provider → the plain active key is mirrored.
        #expect(d.string(forKey: "byok.llm.model") == "qwen3.6-plus")
        #expect(d.string(forKey: "byok.llm.qwen.model") == "qwen3.6-plus")
    }
}
