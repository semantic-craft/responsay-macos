import ResponsayCore
@testable import ResponsaySpeech
import XCTest
@testable import ResponsayMac

final class QwenRunTaskCaptureConfigurationTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "qwen-run-task-capture-configuration-tests"

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

    /// The 千问 card dials the run-task socket. Without a Workspace ID it must keep using the
    /// generic DashScope host, and it must read only the current `byok.qwen-asr-flash` slot.
    @MainActor
    func testQwenRunTaskWithoutWorkspaceUsesGenericHostAndCurrentKeySlot() async throws {
        defaults.set("qwen-asr-flash", forKey: "byok.asr.provider")

        let config = try await captureQwenConfig(
            keyReader: { $0 == "byok.qwen-asr-flash" ? " settings-qwen-key " : nil })

        XCTAssertEqual(config.endpoint.url.absoluteString,
                       "wss://dashscope.aliyuncs.com/api-ws/v1/inference")
        XCTAssertFalse(config.endpoint.usesDedicatedHost)
        XCTAssertEqual(config.apiKey, "settings-qwen-key")
        XCTAssertEqual(config.model, "qwen-audio-3.0-asr-flash-streaming")
    }

    @MainActor
    func testQwenSettingsSurviveQuickProviderReselectionInNextCapture() async throws {
        defaults.set(QwenASRFlashRouting.providerId, forKey: "byok.asr.provider")
        let credentials = ASRCredentialStore()
        let machine = ProviderConfigMachine(
            capability: .asr,
            preferredProviderId: QwenASRFlashRouting.providerId,
            defaults: defaults,
            keyReader: { credentials.read($0) },
            keyWriter: { credentials.write($0, account: $1) })
        machine.load()
        machine.regionRaw = ProviderRegion.singapore.rawValue
        machine.workspaceID = "ws-abc123"
        machine.model = QwenASRFlashRouting.funASRRealtimeModel
        machine.apiKey = "settings-qwen-key"
        machine.writeApiKey()
        machine.refreshBaseURLForSelection()
        machine.persist()

        ModelRouteSelectionActions.applyASRSelection(
            ASREngine.cloudOpenAI.rawValue,
            defaults: defaults)
        ModelRouteSelectionActions.applyASRSelection(
            ASREngine.cloudQwenASRFlashRealtime.rawValue,
            defaults: defaults)
        XCTAssertEqual(
            SettingsASRModelState.effectiveModel(
                providerId: QwenASRFlashRouting.providerId,
                defaults: defaults),
            QwenASRFlashRouting.funASRRealtimeModel)
        XCTAssertFalse(
            SettingsASRModelState.supportsMixedLanguageHints(
                providerId: QwenASRFlashRouting.providerId,
                defaults: defaults))

        let config = try await captureQwenConfig(
            keyReader: { credentials.read($0) })

        XCTAssertEqual(
            config.endpoint.url.absoluteString,
            "wss://ws-abc123.ap-southeast-1.maas.aliyuncs.com/api-ws/v1/inference")
        XCTAssertEqual(config.model, "fun-asr-realtime")
        XCTAssertEqual(config.apiKey, "settings-qwen-key")
    }

    @MainActor
    func testQwenSettingsAndNextCaptureShareNormalizedEffectiveState() async throws {
        defaults.set(QwenASRFlashRouting.providerId, forKey: "byok.asr.provider")
        defaults.set(
            ProviderRegion.unitedStates.rawValue,
            forKey: "byok.asr.qwen-asr-flash.region")
        defaults.set(
            "ws-abc123.evil.example",
            forKey: "byok.asr.qwen-asr-flash.workspaceId")
        defaults.set(
            "wss://dashscope.aliyuncs.com/api-ws/v1/realtime",
            forKey: "byok.asr.qwen-asr-flash.baseURL")
        defaults.set(
            "qwen3-asr-flash-realtime-2026-02-10",
            forKey: "byok.asr.qwen-asr-flash.model")
        let machine = ProviderConfigMachine(
            capability: .asr,
            preferredProviderId: QwenASRFlashRouting.providerId,
            defaults: defaults,
            keyReader: { _ in "settings-qwen-key" })

        machine.load()
        let config = try await captureQwenConfig(
            keyReader: { _ in "settings-qwen-key" })

        let expected = [
            ProviderRegion.china.rawValue,
            "",
            "wss://dashscope.aliyuncs.com/api-ws/v1/inference",
            "qwen-audio-3.0-asr-flash-streaming",
        ]
        XCTAssertEqual(
            [machine.regionRaw, machine.workspaceID, machine.baseURL, machine.model],
            expected)
        XCTAssertEqual(
            [
                config.endpoint.region.rawValue,
                config.endpoint.workspaceID ?? "",
                config.endpoint.url.absoluteString,
                config.model,
            ],
            expected)
    }

    @MainActor
    func testQwenVocabularySettingReachesEachNextCaptureWithoutRestart() async throws {
        defaults.set(QwenASRFlashRouting.providerId, forKey: "byok.asr.provider")
        XCTAssertTrue(ContextHotwordSettings.addManual("Westlaw", defaults: defaults))
        let machine = ProviderConfigMachine(
            capability: .asr,
            preferredProviderId: QwenASRFlashRouting.providerId,
            defaults: defaults,
            keyReader: { _ in "settings-qwen-key" })
        machine.load()
        machine.workspaceID = "ws-first"
        machine.refreshBaseURLForSelection()
        machine.persist()
        machine.precompiledVocabularyID = "vocab-curated-a1b2c3"
        machine.writeQwenPrecompiledVocabulary()

        let synchronized = try await captureQwenConfig(
            keyReader: { _ in "settings-qwen-key" })

        machine.workspaceID = "ws-second"
        machine.refreshBaseURLForSelection()
        machine.persist()
        let changed = try await captureQwenConfig(
            keyReader: { _ in "settings-qwen-key" })

        XCTAssertEqual(synchronized.precompiledVocabularyID, "vocab-curated-a1b2c3")
        XCTAssertTrue(synchronized.hotwords.isEmpty)
        XCTAssertNil(changed.precompiledVocabularyID)
        XCTAssertEqual(changed.hotwords, ["Westlaw"])
        XCTAssertEqual(
            changed.endpoint.url.absoluteString,
            "wss://ws-second.cn-beijing.maas.aliyuncs.com/api-ws/v1/inference")
    }

    @MainActor
    func testQwenRunTaskFallsBackToFullInstantVocabularyAfterLearningMixedTerm() async throws {
        defaults.set("qwen-asr-flash", forKey: "byok.asr.provider")
        XCTAssertTrue(ContextHotwordSettings.addManual("Westlaw", defaults: defaults))
        QwenPrecompiledVocabularySettings.save(
            identifier: "vocab-curated-a1b2c3",
            model: QwenRunTaskEndpoint.defaultModel,
            endpoint: QwenRunTaskEndpoint(region: .china),
            vocabularyTerms: ContextHotwordSettings.qwenPersistentHotwords(defaults: defaults),
            defaults: defaults)
        XCTAssertTrue(ContextHotwordSettings.addAuto("法研 Metis", defaults: defaults))

        let config = try await captureQwenConfig(keyReader: { _ in "k" })

        XCTAssertNil(config.precompiledVocabularyID)
        XCTAssertEqual(Set(config.hotwords), ["Westlaw", "法研 Metis"])
    }

    @MainActor
    func testQwenRunTaskMalformedBindingFailsOpenWithoutExposingItInConfig() async throws {
        defaults.set("qwen-asr-flash", forKey: "byok.asr.provider")
        defaults.set("Metis", forKey: ContextHotwordSettings.defaultsKey)
        defaults.set("not-json", forKey: QwenPrecompiledVocabularySettings.scopedDefaultsKey)

        let config = try await captureQwenConfig(keyReader: { _ in "k" })

        XCTAssertNil(config.precompiledVocabularyID)
        XCTAssertEqual(config.hotwords, ["Metis"])
    }

    @MainActor
    func testQwenRunTaskSingaporeWorkspaceOmitsAllUnsupportedVocabulary() async throws {
        defaults.set("qwen-asr-flash", forKey: "byok.asr.provider")
        defaults.set("singapore", forKey: "byok.asr.qwen-asr-flash.region")
        defaults.set("ws-abc123", forKey: "byok.asr.qwen-asr-flash.workspaceId")
        XCTAssertTrue(ContextHotwordSettings.addManual("法研 Metis", defaults: defaults))
        XCTAssertNil(QwenPrecompiledVocabularySettings.save(
            identifier: "vocab-deadbeef",
            model: QwenRunTaskEndpoint.defaultModel,
            endpoint: QwenRunTaskEndpoint(region: .singapore, workspaceID: "ws-abc123"),
            vocabularyTerms: ContextHotwordSettings.qwenPersistentHotwords(defaults: defaults),
            defaults: defaults))

        let config = try await captureQwenConfig(keyReader: { _ in "k" })

        XCTAssertFalse(config.endpoint.supportsHotwords)
        XCTAssertNil(config.precompiledVocabularyID)
        XCTAssertTrue(config.hotwords.isEmpty)
    }

    @MainActor
    func testQwenUnsupportedVocabularyIsNotUsedForEchoFiltering() async throws {
        defaults.set("qwen-asr-flash", forKey: "byok.asr.provider")
        defaults.set("singapore", forKey: "byok.asr.qwen-asr-flash.region")
        defaults.set("ws-abc123", forKey: "byok.asr.qwen-asr-flash.workspaceId")
        defaults.set("Westlaw, SSRN", forKey: ContextHotwordSettings.defaultsKey)
        let adapter = LocalQwenDictationAdapter(completion: .transcript("Westlaw, SSRN"))
        let router = makeQwenRouter(adapter: adapter)

        try router.start(locale: .mixed)
        let transcript = try await router.stop()

        XCTAssertFalse(try XCTUnwrap(adapter.config).endpoint.supportsHotwords)
        XCTAssertTrue(adapter.config?.hotwords.isEmpty == true)
        XCTAssertEqual(transcript, "Westlaw, SSRN")
    }

    @MainActor
    func testQwenEchoFilteringUsesOnlyFilteredWireVocabulary() async throws {
        defaults.set("qwen-asr-flash", forKey: "byok.asr.provider")
        defaults.set(
            "Westlaw, SSRN, one two three four five six seven eight",
            forKey: ContextHotwordSettings.defaultsKey)
        let adapter = LocalQwenDictationAdapter(completion: .transcript("Westlaw, SSRN"))
        let router = makeQwenRouter(adapter: adapter)

        try router.start(locale: .mixed)
        let transcript = try await router.stop()

        XCTAssertEqual(Set(try XCTUnwrap(adapter.config).hotwords), ["Westlaw", "SSRN"])
        XCTAssertEqual(transcript, "")
    }

    @MainActor
    func testQwenRunTaskPreservesHeartbeatAndProviderVADDefaults() async throws {
        defaults.set("qwen-asr-flash", forKey: "byok.asr.provider")

        let config = try await captureQwenConfig(keyReader: { _ in "k" })
        XCTAssertTrue(config.heartbeat)
    }

    @MainActor
    func testRouterOwnedQwenTermsDoNotLeakAcrossInstances() async throws {
        defaults.set("qwen-asr-flash", forKey: "byok.asr.provider")

        let first = try await captureQwenConfig(
            keyReader: { _ in "k" },
            screenTermHarvester: { terms in
                terms.beginHarvest(
                    isEnabled: true,
                    targetProcessIdentifier: 123,
                    dictionaryTerms: { [] },
                    collect: { _ in
                        try? await Task.sleep(nanoseconds: 20_000_000)
                        return "First Router Screen"
                    })
            })
        let second = try await captureQwenConfig(keyReader: { _ in "k" })

        XCTAssertTrue(first.hotwords.contains("First Router Screen"))
        XCTAssertFalse(second.hotwords.contains("First Router Screen"))
    }

    @MainActor
    func testRecoveredContextFeedsNextQwenCaptureWithoutChangingVocabularyLane() async throws {
        defaults.set("qwen-asr-flash", forKey: "byok.asr.provider")
        XCTAssertTrue(ContextHotwordSettings.addManual("Westlaw", defaults: defaults))
        let binding = QwenPrecompiledVocabularySettings.save(
            identifier: "vocab-context-a1b2c3",
            model: QwenRunTaskEndpoint.defaultModel,
            endpoint: QwenRunTaskEndpoint(region: .china),
            vocabularyTerms: ContextHotwordSettings.qwenPersistentHotwords(defaults: defaults),
            defaults: defaults)
        XCTAssertNotNil(binding)
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("qwen-asr-context-v1.json")
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        XCTAssertTrue(PersistentASRContextSettings.setEnabled(
            true, defaults: defaults, fileURL: fileURL))
        let contextStore = RecentASRContextSessionStore(defaults: defaults, fileURL: fileURL)
        contextStore.record("raw recovered final", scope: "com.apple.Notes")

        let config = try await captureQwenConfig(
            keyReader: { _ in "synthetic-test-key" },
            contextScope: "com.apple.Notes",
            contextStore: contextStore)

        XCTAssertEqual(config.contextScope, "com.apple.Notes")
        XCTAssertEqual(config.context, ["raw recovered final"])
        XCTAssertEqual(config.precompiledVocabularyID, "vocab-context-a1b2c3")
        XCTAssertTrue(config.hotwords.isEmpty)
        XCTAssertTrue(config.heartbeat)
    }

    @MainActor
    private func makeQwenRouter(adapter: LocalQwenDictationAdapter) -> RoutedSpeechCaptureService {
        ModelRouteSelectionActions.applyASRSelection(
            ASREngine.cloudQwenASRFlashRealtime.rawValue,
            defaults: defaults)
        let contextStore = RecentASRContextSessionStore(
            defaults: defaults,
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("qwen-route-\(UUID().uuidString).json"))
        return RoutedSpeechCaptureService(
            contextScopeProvider: { "com.example.Editor" },
            defaults: defaults,
            keyReader: { account in
                account == CapabilityCredentialAccount.apiKeyAccount(
                    providerId: QwenASRFlashRouting.providerId,
                    capability: .asr,
                    plan: .payg)
                    ? "synthetic-qwen-key"
                    : nil
            },
            qwenRunTask: adapter,
            qwenAudioRecorder: { adapter },
            qwenContextStore: contextStore,
            requireQwenMicPermission: {})
    }

    @MainActor
    private func captureQwenConfig(
        keyReader: @escaping ASRKeyReader,
        contextScope: String? = nil,
        contextStore: RecentASRContextSessionStore? = nil,
        screenTermHarvester: ((TransientScreenTerms) -> Void)? = nil
    ) async throws -> QwenRunTaskCaptureConfig {
        ModelRouteSelectionActions.applyASRSelection(
            ASREngine.cloudQwenASRFlashRealtime.rawValue,
            defaults: defaults)
        let adapter = LocalQwenDictationAdapter(completion: .transcript("config captured"))
        let contextStore = contextStore ?? RecentASRContextSessionStore(
            defaults: defaults,
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("qwen-config-\(UUID().uuidString).json"))
        let router = RoutedSpeechCaptureService(
            contextScopeProvider: { contextScope },
            defaults: defaults,
            keyReader: keyReader,
            qwenRunTask: adapter,
            qwenAudioRecorder: { adapter },
            qwenContextStore: contextStore,
            requireQwenMicPermission: {},
            screenTermHarvester: screenTermHarvester)

        try router.start(locale: .mixed)
        _ = try await router.stop()
        return try XCTUnwrap(adapter.config)
    }
}
