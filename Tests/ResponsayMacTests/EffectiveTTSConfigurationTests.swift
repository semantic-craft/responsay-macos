import XCTest
import ResponsayCore
@testable import ResponsayMac
@testable import ResponsaySpeech

private final class TTSEffectiveCredentialStore: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    private var reads: [String] = []

    func read(_ account: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        reads.append(account)
        return values[account]
    }

    func write(_ value: String, account: String) {
        lock.lock()
        defer { lock.unlock() }
        values[account] = value
    }

    func resetReads() {
        lock.lock()
        defer { lock.unlock() }
        reads = []
    }

    var recordedReads: [String] {
        lock.lock()
        defer { lock.unlock() }
        return reads
    }
}

/// Issue #76 — Settings, quick selection, and synthesis consume one effective TTS state.
final class EffectiveTTSConfigurationTests: XCTestCase {
    @MainActor
    func testQwenSettingsAndRuntimeShareEffectiveProviderRules() throws {
        let defaults = freshDefaults("qwen-provider-rules")
        defaults.set("qwen", forKey: "byok.tts.provider")
        defaults.set(ProviderRegion.singapore.rawValue, forKey: "byok.tts.qwen.region")
        defaults.set("qwen3-tts-flash-realtime", forKey: "byok.tts.qwen.model")
        defaults.set("https://dashscope.aliyuncs.com/api/v1", forKey: "byok.tts.qwen.baseURL")
        defaults.set("loongjohn", forKey: "byok.tts.qwen.voice")
        let keyReader: (String) -> String? = { account in
            account == TTSCredential.keychainAccount(for: "qwen") ? "tts-qwen-key" : nil
        }
        let settings = ProviderConfigMachine(
            capability: .tts,
            preferredProviderId: "qwen",
            defaults: defaults,
            keyReader: keyReader)

        settings.load()
        let effective = ProviderConfigDispatcher(defaults: defaults, keyReader: keyReader)
            .resolve(.tts)
        let synthesizer = try TTSEngine.cloudQwen.makeStreamingSynthesizer(
            defaults: defaults,
            keyReader: keyReader)
        let runtime = try XCTUnwrap(synthesizer as? QwenStreamingTTSEngine)

        XCTAssertEqual(settings.regionRaw, effective.region.rawValue)
        XCTAssertEqual(settings.model, effective.model)
        XCTAssertEqual(settings.baseURL, effective.baseURL)
        XCTAssertEqual(runtime.region, .singapore)
        XCTAssertEqual(runtime.model, effective.model)
        XCTAssertEqual(runtime.voice, settings.voice)
        XCTAssertEqual(runtime.key, effective.apiKey)
    }

    @MainActor
    func testSettingsAndQuickSelectionRestoreScopedModelAndVoiceWithoutLeakage() {
        let defaults = freshDefaults("provider-switch")
        let mimoSettings = ProviderConfigMachine(
            capability: .tts,
            preferredProviderId: "mimo",
            defaults: defaults,
            keyReader: { _ in nil })
        mimoSettings.load()
        mimoSettings.model = "custom-mimo-tts"
        mimoSettings.voice = "Mia"
        mimoSettings.persist()
        let qwenSettings = ProviderConfigMachine(
            capability: .tts,
            preferredProviderId: "qwen",
            defaults: defaults,
            keyReader: { _ in nil })
        qwenSettings.load()
        qwenSettings.voice = "loongjohn"
        qwenSettings.persist()

        ModelRouteSelectionActions.applyTTSSelection(
            TTSEngine.cloudMimo.rawValue,
            defaults: defaults)

        let selectedSettings = ProviderConfigMachine(
            capability: .tts,
            preferredProviderId: nil,
            defaults: defaults,
            keyReader: { _ in nil })
        selectedSettings.load()
        var effective = ProviderConfigDispatcher(defaults: defaults, keyReader: { _ in nil })
            .resolve(.tts)

        XCTAssertEqual(effective.providerId, "mimo")
        XCTAssertEqual(effective.model, "custom-mimo-tts")
        XCTAssertEqual(effective.voice, "Mia")
        XCTAssertEqual(selectedSettings.model, effective.model)
        XCTAssertEqual(selectedSettings.voice, effective.voice)

        ModelRouteSelectionActions.applyTTSSelection(
            TTSEngine.cloudQwen.rawValue,
            defaults: defaults)
        effective = ProviderConfigDispatcher(defaults: defaults, keyReader: { _ in nil })
            .resolve(.tts)

        XCTAssertEqual(effective.providerId, "qwen")
        XCTAssertEqual(effective.model, "qwen-audio-3.0-tts-flash")
        XCTAssertEqual(effective.voice, "loongjohn")
        XCTAssertNotEqual(effective.model, "custom-mimo-tts")
        XCTAssertNotEqual(effective.voice, "Mia")

        ModelRouteSelectionActions.applyTTSSelection(
            TTSEngine.cloudMimo.rawValue,
            defaults: defaults)
        effective = ProviderConfigDispatcher(defaults: defaults, keyReader: { _ in nil })
            .resolve(.tts)

        XCTAssertEqual(effective.model, "custom-mimo-tts")
        XCTAssertEqual(effective.voice, "Mia")
        let restoredSettings = ProviderConfigMachine(
            capability: .tts,
            preferredProviderId: nil,
            defaults: defaults,
            keyReader: { _ in nil })
        restoredSettings.load()
        XCTAssertEqual(restoredSettings.model, effective.model)
        XCTAssertEqual(restoredSettings.voice, effective.voice)
    }

    @MainActor
    func testPlanScopedSettingsReachTheNextSynthesisRequest() async throws {
        let defaults = freshDefaults("plan-scoped-runtime")
        defaults.set(TTSEngine.cloudMimo.rawValue, forKey: TTSEngine.defaultsKey)
        let credentials = TTSEffectiveCredentialStore()
        let settings = ProviderConfigMachine(
            capability: .tts,
            preferredProviderId: "mimo",
            defaults: defaults,
            keyReader: { credentials.read($0) },
            keyWriter: { credentials.write($0, account: $1) })
        settings.load()
        settings.planRaw = BillingPlan.package.rawValue
        settings.model = "mimo-v2.5-tts"
        settings.voice = "Mia"
        settings.refreshBaseURLForSelection()
        settings.apiKey = "tp-settings-key"
        settings.writeApiKey()
        settings.persist()

        let effective = ProviderConfigDispatcher(
            defaults: defaults,
            keyReader: { credentials.read($0) })
            .resolve(.tts, providerId: "mimo")
        XCTAssertEqual(effective.plan, .package)
        XCTAssertEqual(effective.baseURL, "https://token-plan-cn.xiaomimimo.com/v1")
        XCTAssertEqual(effective.model, "mimo-v2.5-tts")
        XCTAssertEqual(effective.voice, "Mia")
        XCTAssertEqual(effective.apiKey, "tp-settings-key")

        let response = try JSONSerialization.data(withJSONObject: [
            "choices": [[
                "message": [
                    "audio": ["data": TTSTestAudio.wav([0, 0.5]).base64EncodedString()],
                ],
            ]],
        ])
        StubURLProtocol.lastRequest = nil
        StubURLProtocol.lastRequestBody = nil
        StubURLProtocol.handler = { _ in (200, response) }
        defer {
            StubURLProtocol.handler = nil
            StubURLProtocol.lastRequest = nil
            StubURLProtocol.lastRequestBody = nil
        }

        credentials.resetReads()
        let synthesizer = try TTSEngine.selected(defaults: defaults).makeSynthesizer(
            defaults: defaults,
            session: StubURLProtocol.session(),
            keyReader: { credentials.read($0) })
        _ = try await synthesizer.synthesize("hello", speed: 1)

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://token-plan-cn.xiaomimimo.com/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "api-key"), "tp-settings-key")
        let body = try JSONSerialization.jsonObject(
            with: try XCTUnwrap(StubURLProtocol.lastRequestBody)) as? [String: Any]
        XCTAssertEqual(body?["model"] as? String, "mimo-v2.5-tts")
        XCTAssertEqual((body?["audio"] as? [String: Any])?["voice"] as? String, "Mia")
        XCTAssertEqual(
            credentials.recordedReads,
            [CapabilityCredentialAccount.apiKeyAccount(
                providerId: "mimo",
                capability: .tts,
                plan: .package)])
    }

    private func freshDefaults(_ suffix: String) -> UserDefaults {
        let name = "EffectiveTTSConfigurationTests.\(suffix)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
