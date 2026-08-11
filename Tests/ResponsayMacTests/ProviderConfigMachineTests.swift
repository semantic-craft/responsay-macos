import Testing
import Foundation
@testable import ResponsayMac
@testable import ResponsayCore

/// Unit coverage for the provider-config logic extracted out of `CapabilityCardView` into
/// `ProviderConfigMachine`. These drive the machine directly (no SwiftUI rendering), asserting
/// the deterministic plan→model routing, endpoint picking, `load()` seeding (incl. the
/// fixed-endpoint 豆包流式 ASR engine) and `endpointBase()` derivation.
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
            capability: capability,
            preferredProviderId: preferred,
            defaults: freshDefaults(suffix),
            keyReader: { _ in nil })
    }

    // MARK: - load(): default provider seeding

    @Test func loadSeedsQwenLLMDefaultsFromEmptyStore() {
        let m = machine(.llm, suffix: "load-qwen-llm")
        m.load()
        #expect(m.providerId == "qwen")
        #expect(m.region == .china)
        #expect(m.plan == .payg)
        #expect(m.model == "qwen3.7-flash")
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
        let m = ProviderConfigMachine(
            capability: .llm, preferredProviderId: nil, defaults: d, keyReader: { _ in nil })
        m.load()
        #expect(m.providerId == "openai")
        #expect(m.model == "gpt-custom")
        #expect(m.baseURL == "https://api.openai.com/v1")
    }

    @Test func loadResolvesAnInvalidQwenVoiceTheSameWayAsTheReaderWithoutRewritingIt() {
        let d = freshDefaults("load-resolves-invalid-qwen-voice")
        d.set("qwen", forKey: "byok.tts.provider")
        d.set("unsupported-qwen-voice", forKey: "byok.tts.voice")
        d.set("unsupported-qwen-voice", forKey: "byok.tts.qwen.voice")
        d.set("longjielidou_v3.6", forKey: "ttsVoice.cloud-qwen-tts")
        let m = ProviderConfigMachine(
            capability: .tts, preferredProviderId: nil, defaults: d, keyReader: { _ in nil })

        m.load()

        #expect(m.voice == "loongeva_v3.6")
        #expect(m.voice == TTSEngine.cloudQwen.selectedVoiceID(defaults: d))
        #expect(d.string(forKey: "byok.tts.voice") == "unsupported-qwen-voice")
        #expect(d.string(forKey: "byok.tts.qwen.voice") == "unsupported-qwen-voice")
    }

    @Test func openTTSConfigRefreshesAfterTheReaderChangesVoice() {
        let d = freshDefaults("open-tts-config-refreshes-voice")
        d.set("qwen", forKey: "byok.tts.provider")
        let m = ProviderConfigMachine(
            capability: .tts, preferredProviderId: nil, defaults: d, keyReader: { _ in nil })
        m.load()
        #expect(m.voice == "loongeva_v3.6")

        TTSEngine.cloudQwen.setSelectedVoiceID("longjielidou_v3.6", defaults: d)
        m.refreshVoiceFromDefaults()

        #expect(m.voice == "longjielidou_v3.6")
    }

    @Test func loadReadsQwenWorkspaceIDAndDerivesDedicatedResponsesEndpoint() {
        let d = freshDefaults("load-qwen-workspace")
        d.set("qwen", forKey: "byok.llm.provider")
        d.set("ws-abc123", forKey: "byok.llm.qwen.workspaceId")
        let m = ProviderConfigMachine(
            capability: .llm, preferredProviderId: nil, defaults: d, keyReader: { _ in nil })

        m.load()

        #expect(m.workspaceID == "ws-abc123")
        #expect(m.baseURL == "https://ws-abc123.cn-beijing.maas.aliyuncs.com/compatible-mode/v1")
    }

    @Test func loadIsIdempotent() {
        let m = machine(.llm, suffix: "load-idempotent")
        m.load()
        m.model = "hand-edited"
        m.load()  // second call is a no-op; must not clobber
        #expect(m.model == "hand-edited")
    }

    // MARK: - load(): fixed-endpoint 实时流式 ASR engines

    @Test func qwenVocabularyBindingBecomesStaleInsteadOfFollowingAWorkspaceChange() {
        let d = freshDefaults("qwen-vocabulary-stale")
        d.set("qwen-asr-flash", forKey: "byok.asr.provider")
        let m = ProviderConfigMachine(
            capability: .asr, preferredProviderId: nil, defaults: d, keyReader: { _ in nil })
        m.load()
        m.workspaceID = "ws-first"
        m.precompiledVocabularyID = "vocab-curated-a1b2c3"
        m.writeQwenPrecompiledVocabulary()

        m.workspaceID = "ws-second"

        #expect(m.qwenVocabularyValidationMessage != nil)
        #expect(QwenPrecompiledVocabularySettings.binding(defaults: d)?.workspaceID == "ws-first")
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
        d.set("volcengine-flash", forKey: "byok.asr.provider")
        // Stale batch config a user could have from before the realtime migration.
        d.set("https://stale.example.com/v1", forKey: "byok.asr.volcengine-flash.baseURL")
        d.set("stale-batch-model", forKey: "byok.asr.volcengine-flash.model")
        let m = ProviderConfigMachine(
            capability: .asr, preferredProviderId: nil, defaults: d, keyReader: { _ in nil })
        m.load()
        #expect(m.baseURL == "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_nostream")
        #expect(m.model == "bigmodel")
        // …and the forced values are persisted back so ModelLaneDisplay reflects them.
        #expect(d.string(forKey: "byok.asr.volcengine-flash.baseURL")
                == "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_nostream")
        #expect(d.string(forKey: "byok.asr.volcengine-flash.model") == "bigmodel")
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

    @Test func selectingQwenResolvesItsInvalidScopedVoiceWithoutRewritingIt() {
        let d = freshDefaults("select-qwen-resolves-invalid-voice")
        d.set("openai", forKey: "byok.tts.provider")
        d.set("unsupported-qwen-voice", forKey: "byok.tts.qwen.voice")
        let m = ProviderConfigMachine(
            capability: .tts, preferredProviderId: "openai", defaults: d, keyReader: { _ in nil })
        m.load()

        m.providerId = "qwen"
        m.selectProvider()

        #expect(m.voice == "loongeva_v3.6")
        #expect(d.string(forKey: "byok.tts.qwen.voice") == "unsupported-qwen-voice")
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

    @Test func endpointBaseFollowsRegionForQwenLLM() {
        let m = machine(.llm, suffix: "endpoint-base")
        m.load()  // qwen · china · payg

        m.regionRaw = ProviderRegion.china.rawValue
        m.planRaw = BillingPlan.payg.rawValue
        #expect(m.endpointBase() == "https://dashscope.aliyuncs.com/compatible-mode/v1")

        m.regionRaw = ProviderRegion.singapore.rawValue
        #expect(m.endpointBase() == "https://dashscope-intl.aliyuncs.com/compatible-mode/v1")

        m.regionRaw = ProviderRegion.unitedStates.rawValue
        #expect(m.endpointBase() == "https://dashscope-us.aliyuncs.com/compatible-mode/v1")
    }

    @Test func qwenWorkspaceEndpointFollowsRegionAndRejectsUnsafeHostInput() {
        #expect(QwenWorkspaceEndpoint.baseURL(workspaceID: " ws-abc123 ", region: .china)
            == "https://ws-abc123.cn-beijing.maas.aliyuncs.com/compatible-mode/v1")
        #expect(QwenWorkspaceEndpoint.baseURL(workspaceID: "ws-abc123", region: .singapore)
            == "https://ws-abc123.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1")
        #expect(QwenWorkspaceEndpoint.baseURL(workspaceID: "ws-abc123", region: .germany)
            == "https://ws-abc123.eu-central-1.maas.aliyuncs.com/compatible-mode/v1")
        #expect(QwenWorkspaceEndpoint.baseURL(workspaceID: "ws-abc123", region: .japan)
            == "https://ws-abc123.ap-northeast-1.maas.aliyuncs.com/compatible-mode/v1")
        #expect(QwenWorkspaceEndpoint.baseURL(workspaceID: "ws-abc123", region: .unitedStates) == nil)
        #expect(QwenWorkspaceEndpoint.baseURL(workspaceID: "ws-abc123", region: .global) == nil)
        #expect(QwenWorkspaceEndpoint.baseURL(workspaceID: "ws-abc123.evil.example", region: .china) == nil)
        #expect(QwenWorkspaceEndpoint.baseURL(workspaceID: "https://evil.example", region: .china) == nil)
    }

    @Test func qwenWorkspaceIDChangeDerivesEndpointOrFallsBackToGenericHost() {
        let m = machine(.llm, suffix: "workspace-change")
        m.load()

        m.workspaceID = "ws-abc123"
        m.refreshBaseURLForSelection()
        #expect(m.usesQwenWorkspaceEndpoint)
        #expect(m.baseURL == "https://ws-abc123.cn-beijing.maas.aliyuncs.com/compatible-mode/v1")

        m.workspaceID = ""
        m.refreshBaseURLForSelection()
        #expect(!m.usesQwenWorkspaceEndpoint)
        #expect(m.baseURL == "https://dashscope.aliyuncs.com/compatible-mode/v1")
    }

    // MARK: - autoSwitchModel(): retarget only when uncustomized

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
        let m = ProviderConfigMachine(
            capability: .llm, preferredProviderId: nil, defaults: d, keyReader: { _ in nil })
        m.load()  // qwen
        m.model = "qwen3.7-plus"
        m.workspaceID = "ws-abc123"
        m.refreshBaseURLForSelection()
        m.persist()
        #expect(d.string(forKey: "byok.llm.qwen.model") == "qwen3.7-plus")
        #expect(d.string(forKey: "byok.llm.qwen.region") == ProviderRegion.china.rawValue)
        #expect(d.string(forKey: "byok.llm.qwen.plan") == BillingPlan.payg.rawValue)
        #expect(d.string(forKey: "byok.llm.qwen.workspaceId") == "ws-abc123")
        #expect(d.string(forKey: "byok.llm.qwen.baseURL")
            == "https://ws-abc123.cn-beijing.maas.aliyuncs.com/compatible-mode/v1")
    }

    @Test func persistMirrorsToActiveKeyWhenProviderMatchesStored() {
        let d = freshDefaults("persist-active-mirror")
        d.set("qwen", forKey: "byok.llm.provider")
        let m = ProviderConfigMachine(
            capability: .llm, preferredProviderId: nil, defaults: d, keyReader: { _ in nil })
        m.load()
        m.model = "qwen3.6-plus"
        m.persist()
        // Active provider == the machine's provider → the plain active key is mirrored.
        #expect(d.string(forKey: "byok.llm.model") == "qwen3.6-plus")
        #expect(d.string(forKey: "byok.llm.qwen.model") == "qwen3.6-plus")
    }
}
