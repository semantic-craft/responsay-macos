import XCTest
import ResponsayCore
@testable import ResponsayMac

/// 听写 / 技能平台分模型（同一提供商下的模型分流）。
/// `resolveText` 继续供听写整理、意图编译、改写、翻译、表达；`resolveSkill` 供
/// `RoutingLegalSkillExecutor`（技能执行 + JSON 修复 + 技能搜索）。两条 lane 只允许
/// model 不同 —— provider / Base URL / Workspace 派生 / 凭据必须始终一致。
final class SkillPlatformModelRoutingTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "test.skillPlatformModelRouting"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    private func dispatcher(keys: [String: String] = ["byok.qwen": "sk-shared"]) -> ProviderConfigDispatcher {
        ProviderConfigDispatcher(defaults: defaults, keyReader: { keys[$0] })
    }

    private func selectQwenWithSkillMax() {
        defaults.set("qwen", forKey: "byok.llm.provider")
        SkillPlatformModelSettings.setExplicitModel("qwen3.7-max", providerId: "qwen", defaults: defaults)
    }

    // 1. 听写 Flash + 技能 Max：两条真实 resolver 返回不同 model。
    func test_dictationFlash_skillMax_resolversDiverge() {
        selectQwenWithSkillMax()
        let dictation = LLMEndpointResolver.resolveText(defaults: defaults, dispatcher: dispatcher())
        let skill = LLMEndpointResolver.resolveSkill(defaults: defaults, dispatcher: dispatcher())
        XCTAssertEqual(dictation?.model, "qwen3.7-flash")   // provider default stays the dictation model
        XCTAssertEqual(skill?.model, "qwen3.7-max")
    }

    // 2. 两条 resolver 共享 provider / Base URL / Workspace 派生 / 凭据。
    func test_bothLanes_shareProviderBaseURLWorkspaceAndKey() {
        selectQwenWithSkillMax()
        defaults.set("ws-abc123", forKey: "byok.llm.qwen.workspaceId")
        let dictation = LLMEndpointResolver.resolveText(defaults: defaults, dispatcher: dispatcher())
        let skill = LLMEndpointResolver.resolveSkill(defaults: defaults, dispatcher: dispatcher())
        XCTAssertEqual(dictation?.providerId, "qwen")
        XCTAssertEqual(skill?.providerId, "qwen")
        XCTAssertEqual(dictation?.baseURL, skill?.baseURL)
        XCTAssertTrue(skill?.baseURL.contains("ws-abc123") ?? false)   // workspace 域名两边同源
        XCTAssertEqual(dictation?.apiKey, "sk-shared")
        XCTAssertEqual(skill?.apiKey, "sk-shared")
        XCTAssertEqual(skill?.thinkingEnabled, false)
    }

    // 3. 改技能模型不动听写模型。
    func test_settingSkillModel_doesNotTouchDictationModel() {
        defaults.set("qwen", forKey: "byok.llm.provider")
        defaults.set("qwen3.7-flash", forKey: "byok.llm.qwen.model")
        SkillPlatformModelSettings.setExplicitModel("qwen3.7-max", providerId: "qwen", defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: "byok.llm.qwen.model"), "qwen3.7-flash")
        let dictation = LLMEndpointResolver.resolveText(defaults: defaults, dispatcher: dispatcher())
        XCTAssertEqual(dictation?.model, "qwen3.7-flash")
    }

    // 4. 改听写模型不覆盖显式技能模型。
    func test_changingDictationModel_keepsExplicitSkillModel() {
        selectQwenWithSkillMax()
        defaults.set("qwen3.6-flash", forKey: "byok.llm.qwen.model")   // user re-picks dictation
        let dictation = LLMEndpointResolver.resolveText(defaults: defaults, dispatcher: dispatcher())
        let skill = LLMEndpointResolver.resolveSkill(defaults: defaults, dispatcher: dispatcher())
        XCTAssertEqual(dictation?.model, "qwen3.6-flash")
        XCTAssertEqual(skill?.model, "qwen3.7-max")
    }

    // 5. 「跟随」状态下听写模型变化会正确反映到技能 lane。
    func test_followMode_tracksDictationModelChanges() {
        defaults.set("qwen", forKey: "byok.llm.provider")
        XCTAssertNil(SkillPlatformModelSettings.explicitModel(providerId: "qwen", defaults: defaults))
        XCTAssertEqual(
            LLMEndpointResolver.resolveSkill(defaults: defaults, dispatcher: dispatcher())?.model,
            "qwen3.7-flash")
        defaults.set("qwen3.7-plus", forKey: "byok.llm.qwen.model")
        XCTAssertEqual(
            LLMEndpointResolver.resolveSkill(defaults: defaults, dispatcher: dispatcher())?.model,
            "qwen3.7-plus")   // follows the new dictation model
    }

    // 5b. 显式选择后清空（恢复跟随）同样生效。
    func test_clearingExplicitSkillModel_restoresFollow() {
        selectQwenWithSkillMax()
        SkillPlatformModelSettings.setExplicitModel(nil, providerId: "qwen", defaults: defaults)
        XCTAssertNil(SkillPlatformModelSettings.explicitModel(providerId: "qwen", defaults: defaults))
        XCTAssertEqual(
            LLMEndpointResolver.resolveSkill(defaults: defaults, dispatcher: dispatcher())?.model,
            "qwen3.7-flash")
    }

    // 6. 未设置技能字段时，两条 lane 完全一致。
    func test_configWithoutSkillFieldUsesTheDictationModelForBothLanes() {
        defaults.set("qwen", forKey: "byok.llm.provider")
        defaults.set("qwen3.6-flash", forKey: "byok.llm.qwen.model")   // 既有用户显式保存的旧模型
        let dictation = LLMEndpointResolver.resolveText(defaults: defaults, dispatcher: dispatcher())
        let skill = LLMEndpointResolver.resolveSkill(defaults: defaults, dispatcher: dispatcher())
        XCTAssertEqual(dictation?.model, "qwen3.6-flash")
        XCTAssertEqual(skill?.model, "qwen3.6-flash")       // 无新字段 → 跟随，不引入行为变化
        XCTAssertEqual(dictation?.baseURL, skill?.baseURL)
    }

    /// The obsolete providerless skill-model key may contain a model from a previously selected
    /// provider. The skill lane ignores it and follows dictation instead of sending that foreign
    /// model identifier to the current endpoint.
    func testStaleActiveSkillModelCannotLeakIntoCurrentProvider() {
        defaults.set("qwen", forKey: "byok.llm.provider")
        defaults.set("qwen3.7-plus", forKey: "byok.llm.qwen.model")
        defaults.set("deepseek-v4-flash", forKey: "byok.llm.skillModel")

        let dictation = LLMEndpointResolver.resolveText(defaults: defaults, dispatcher: dispatcher())
        let skill = LLMEndpointResolver.resolveSkill(defaults: defaults, dispatcher: dispatcher())

        XCTAssertEqual(dictation?.model, "qwen3.7-plus")
        XCTAssertEqual(skill?.model, dictation?.model)
        XCTAssertEqual(skill?.providerId, dictation?.providerId)
        XCTAssertEqual(skill?.baseURL, dictation?.baseURL)
        XCTAssertEqual(skill?.apiKey, dictation?.apiKey)
    }

    /// Persisted values can be syntactically valid yet unsupported by the selected provider.
    /// The settings machine must show the exact normalized state that both runtime lanes consume.
    @MainActor
    func testSettingsAndRuntimeShareNormalizedEffectiveLLMState() {
        defaults.set("qwen", forKey: "byok.llm.provider")
        defaults.set(ProviderRegion.europe.rawValue, forKey: "byok.llm.qwen.region")
        defaults.set(
            "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
            forKey: "byok.llm.qwen.baseURL")
        defaults.set("   ", forKey: "byok.llm.qwen.model")
        defaults.set("ws-abc123.evil.example", forKey: "byok.llm.qwen.workspaceId")
        defaults.set("deepseek-v4-flash", forKey: "byok.llm.skillModel")
        let keyReader: (String) -> String? = { _ in "sk-effective" }
        let machine = ProviderConfigMachine(
            capability: .llm,
            preferredProviderId: nil,
            defaults: defaults,
            keyReader: keyReader)

        machine.load()
        let lanes = ProviderConfigDispatcher(defaults: defaults, keyReader: keyReader).resolveLLM()

        XCTAssertEqual(machine.providerId, lanes.provider.providerId)
        XCTAssertEqual(machine.regionRaw, lanes.provider.region.rawValue)
        XCTAssertEqual(machine.planRaw, lanes.provider.plan.rawValue)
        XCTAssertEqual(machine.workspaceID, lanes.provider.workspaceID ?? "")
        XCTAssertEqual(machine.baseURL, lanes.provider.baseURL)
        XCTAssertEqual(machine.model, lanes.dictationEndpoint.model)
        XCTAssertEqual(machine.skillModel, lanes.explicitSkillModel ?? "")
        XCTAssertEqual(machine.apiKey, lanes.dictationEndpoint.apiKey)
        XCTAssertEqual(lanes.provider.region, .china)
        XCTAssertEqual(
            lanes.provider.baseURL,
            "https://dashscope.aliyuncs.com/compatible-mode/v1")
        XCTAssertEqual(lanes.skillEndpoint.model, lanes.dictationEndpoint.model)
        XCTAssertEqual(lanes.skillEndpoint.baseURL, lanes.dictationEndpoint.baseURL)
        XCTAssertEqual(lanes.skillEndpoint.apiKey, lanes.dictationEndpoint.apiKey)
    }

    /// Settings can prepare a provider-scoped selection before it becomes active. A quick-picker
    /// plan switch must persist one valid region/plan pair, preserve a custom dictation model, and
    /// make both runtime lanes consume the credential belonging to the selected plan.
    @MainActor
    func testPersistedSettingsFlowThroughQuickSelectionIntoBothRuntimeLanes() {
        defaults.set("qwen", forKey: "byok.llm.provider")
        let keys = [
            "byok.mimo.package": "tp-package",
            "byok.mimo.payg": "sk-payg",
        ]
        let keyReader: (String) -> String? = { keys[$0] }
        let settings = ProviderConfigMachine(
            capability: .llm,
            preferredProviderId: "mimo",
            defaults: defaults,
            keyReader: keyReader)
        settings.load()
        settings.regionRaw = ProviderRegion.singapore.rawValue
        settings.planRaw = BillingPlan.package.rawValue
        settings.refreshBaseURLForSelection()
        settings.model = "mimo-v2.5-pro"
        settings.skillModel = ""
        settings.persist()

        ModelRouteSelectionActions.applyLLMSelection("mimo#payg", defaults: defaults)

        let dispatcher = ProviderConfigDispatcher(defaults: defaults, keyReader: keyReader)
        let effective = dispatcher.resolveLLM()
        let dictation = LLMEndpointResolver.resolveText(defaults: defaults, dispatcher: dispatcher)
        let skill = LLMEndpointResolver.resolveSkill(defaults: defaults, dispatcher: dispatcher)
        XCTAssertEqual(effective.provider.providerId, "mimo")
        XCTAssertEqual(effective.provider.region, .china)
        XCTAssertEqual(effective.provider.plan, .payg)
        XCTAssertEqual(effective.provider.baseURL, "https://api.xiaomimimo.com/v1")
        XCTAssertEqual(effective.provider.model, "mimo-v2.5-pro")
        XCTAssertEqual(defaults.string(forKey: "byok.llm.mimo.region"), ProviderRegion.china.rawValue)
        XCTAssertEqual(defaults.string(forKey: "byok.llm.mimo.plan"), BillingPlan.payg.rawValue)
        XCTAssertEqual(defaults.string(forKey: "byok.llm.mimo.model"), "mimo-v2.5-pro")
        XCTAssertEqual(dictation?.apiKey, "sk-payg")
        XCTAssertEqual(skill?.apiKey, dictation?.apiKey)
        XCTAssertEqual(skill?.providerId, dictation?.providerId)
        XCTAssertEqual(skill?.baseURL, dictation?.baseURL)
        XCTAssertEqual(skill?.model, dictation?.model)
    }

    /// A caller may ask the effective resolver to preview a different billing plan before any
    /// persistence occurs. The endpoint and credential must move together in that snapshot.
    func testPlanOverrideCannotMixStoredEndpointWithSelectedCredential() {
        defaults.set("mimo", forKey: "byok.llm.provider")
        defaults.set(ProviderRegion.china.rawValue, forKey: "byok.llm.mimo.region")
        defaults.set(BillingPlan.package.rawValue, forKey: "byok.llm.mimo.plan")
        defaults.set("https://token-plan-cn.xiaomimimo.com/v1", forKey: "byok.llm.mimo.baseURL")
        let lanes = dispatcher(keys: [
            "byok.mimo.package": "tp-package",
            "byok.mimo.payg": "sk-payg",
        ]).resolveLLM(providerId: "mimo", plan: .payg)

        XCTAssertEqual(lanes.provider.plan, .payg)
        XCTAssertEqual(lanes.provider.baseURL, "https://api.xiaomimimo.com/v1")
        XCTAssertEqual(lanes.provider.apiKey, "sk-payg")
        XCTAssertEqual(lanes.dictationEndpoint.baseURL, lanes.skillEndpoint.baseURL)
        XCTAssertEqual(lanes.dictationEndpoint.apiKey, lanes.skillEndpoint.apiKey)
        XCTAssertEqual(defaults.string(forKey: "byok.llm.mimo.plan"), BillingPlan.package.rawValue)
        XCTAssertEqual(
            defaults.string(forKey: "byok.llm.mimo.baseURL"),
            "https://token-plan-cn.xiaomimimo.com/v1")
    }

    // 7. Qwen 技能模型列表包含 qwen3.7-max（否则 LLMModelPresetFilter 会把拉取结果过滤掉）。
    func test_qwenPresetModels_includeMax_forSkillPicker() {
        let qwen = ProviderCatalog.presets(for: .llm).first { $0.id == "qwen" }
        let models = qwen?.presetModels[.llm] ?? []
        XCTAssertTrue(models.contains("qwen3.7-max"))
        XCTAssertEqual(qwen?.defaultModels[.llm], "qwen3.7-flash")   // 产品默认不变
        // 过滤器不吞 Max：/models 返回包含 Max 时保留。
        let filtered = LLMModelPresetFilter.models(
            from: ["qwen3.7-flash", "qwen3.7-max", "unrelated-asr"], preset: qwen!, capability: .llm)
        XCTAssertTrue(filtered.contains("qwen3.7-max"))
    }

    // 11. readiness / 设置快照区分两个模型选择。
    // 驼峰命名（本文件其余用 test_ 下划线风格）：`test_` + 长标识符会被 TruffleHog 的 Lob
    // 检测器当成 `test_<key>` 形态的 API key，让 CI 的 secret scan 误报失败。
    func testLaneSnapshotDistinguishesTwoModels() {
        selectQwenWithSkillMax()
        let display = ModelLaneDisplay(
            defaults: defaults,
            readiness: ModelLaneReadinessResolver(
                dispatcher: dispatcher(),
                ocrKeyReader: { _ in nil },
                asrLocalInstalled: { _ in true },
                ttsLocalInstalled: { true },
                ocrLocalInstalled: { false }))
        let llm = display.lanes().first { $0.lane == .llm }!
        XCTAssertEqual(llm.modelId, "qwen3.7-flash · 技能 qwen3.7-max")
        XCTAssertTrue(llm.readiness.isReady)   // 同一密钥，两个选择同享 readiness

        // 跟随时保持单模型显示，不引入噪音。
        SkillPlatformModelSettings.setExplicitModel(nil, providerId: "qwen", defaults: defaults)
        let followed = display.lanes().first { $0.lane == .llm }!
        XCTAssertEqual(followed.modelId, "qwen3.7-flash")
    }

    // 12. 不影响 ASR / TTS / OCR：技能模型键只存在于 llm 能力下。
    func test_skillModelKey_isLLMOnly_andProviderScoped() {
        selectQwenWithSkillMax()
        XCTAssertNil(defaults.string(forKey: "byok.asr.skillModel"))
        XCTAssertNil(defaults.string(forKey: "byok.tts.skillModel"))
        XCTAssertNil(defaults.string(forKey: "byok.llm.skillModel"))

        // 切换提供商：新提供商默认跟随，scoped 保留（切回恢复），且不创建无身份镜像。
        ModelRouteSelectionActions.applyLLMSelection("deepseek", defaults: defaults)
        XCTAssertNil(defaults.string(forKey: "byok.llm.skillModel"))
        XCTAssertNil(SkillPlatformModelSettings.explicitModel(providerId: "deepseek", defaults: defaults))
        XCTAssertEqual(defaults.string(forKey: "byok.llm.qwen.skillModel"), "qwen3.7-max")
        ModelRouteSelectionActions.applyLLMSelection("qwen", defaults: defaults)
        XCTAssertEqual(SkillPlatformModelSettings.explicitModel(providerId: "qwen", defaults: defaults), "qwen3.7-max")
    }

    // ProviderConfigMachine：卡片状态与持久化（跟随语义 + llm-only 写入）。
    @MainActor
    func test_machinePersistsSkillModel_llmOnly() {
        defaults.set("qwen", forKey: "byok.llm.provider")
        let machine = ProviderConfigMachine(
            capability: .llm,
            preferredProviderId: nil,
            defaults: defaults,
            keyReader: { _ in nil })
        machine.load()
        XCTAssertEqual(machine.skillModel, "")               // 默认跟随
        machine.skillModel = "qwen3.7-max"
        machine.persist()
        XCTAssertEqual(defaults.string(forKey: "byok.llm.qwen.skillModel"), "qwen3.7-max")
        XCTAssertEqual(defaults.string(forKey: "byok.llm.qwen.model"), machine.model)   // 听写模型未被牵动

        let asrMachine = ProviderConfigMachine(
            capability: .asr,
            preferredProviderId: nil,
            defaults: defaults,
            keyReader: { _ in nil })
        asrMachine.load()
        asrMachine.persist()
        XCTAssertNil(defaults.string(forKey: "byok.asr.\(asrMachine.providerId).skillModel"))
    }
}
