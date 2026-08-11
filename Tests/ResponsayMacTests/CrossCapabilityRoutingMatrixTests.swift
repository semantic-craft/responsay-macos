import XCTest
import ResponsayCore
@testable import ResponsaySpeech
@testable import ResponsayMac

/// ASR / LLM / TTS are three independent route choices. This matrix pins the
/// common local/cloud combinations so local ASR/TTS models can be mixed with the
/// cloud text model without leaking keys or silently changing another capability.
final class CrossCapabilityRoutingMatrixTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "test.crossCapabilityRoutingMatrix"
    // Multi-plan MiMo routes store keys per plan; single-plan Qwen LLM uses its base slot.
    private static let keys: [String: String] = [
        "byok.qwen-asr-flash": "asr-qwen-flash-key",
        "byok.mimo.package": "mimo-shared-key",
        "byok.openai": "asr-openai-key",
        "byok.qwen": "llm-qwen-key",
        "byok.deepseek": "llm-deepseek-key",
        "byok.tts.qwen": "tts-qwen-key",
        "byok.tts.mimo.payg": "tts-mimo-key",
        "byok.tts.openai": "tts-openai-key",
    ]

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

    func testOfflineCloudRouteCombinationsStayIndependent() throws {
        let scenarios: [Scenario] = [
            Scenario(
                name: "SenseVoice ASR + Qwen LLM + Qwen TTS",
                asr: .local(.sensevoiceLocal),
                llm: .cloud("qwen", keyAccount: "byok.qwen", expectedModel: "qwen3.7-flash"),
                tts: .cloud(.cloudQwen, keyAccount: "byok.tts.qwen", expectedModel: "qwen-audio-3.0-tts-flash")),
            Scenario(
                name: "Qwen3 local ASR + MiMo LLM + local Kokoro TTS",
                asr: .local(.qwen3LocalASR),
                llm: .cloud("mimo", keyAccount: "byok.mimo.package", expectedModel: "mimo-v2.5"),
                tts: .local(.sherpaKokoroLocal)),
            Scenario(
                name: "MiMo ASR + Qwen LLM + Qwen TTS",
                asr: .cloud(.cloudMimo, providerId: "mimo", keyAccount: "byok.mimo.package", expectedModel: "mimo-v2.5-asr"),
                llm: .cloud("qwen", keyAccount: "byok.qwen", expectedModel: "qwen3.7-flash"),
                tts: .cloud(.cloudQwen, keyAccount: "byok.tts.qwen", expectedModel: "qwen-audio-3.0-tts-flash")),
            Scenario(
                name: "千问实时 ASR + Qwen LLM + local Kokoro TTS",
                asr: .cloud(.cloudQwenASRFlashRealtime, providerId: "qwen-asr-flash", keyAccount: "byok.qwen-asr-flash", expectedModel: "qwen-audio-3.0-asr-flash-streaming"),
                llm: .cloud("qwen", keyAccount: "byok.qwen", expectedModel: "qwen3.7-flash"),
                tts: .local(.sherpaKokoroLocal)),
            Scenario(
                name: "OpenAI ASR + DeepSeek LLM + OpenAI TTS",
                asr: .cloud(.cloudOpenAI, providerId: "openai", keyAccount: "byok.openai", expectedModel: "gpt-4o-transcribe"),
                llm: .cloud("deepseek", keyAccount: "byok.deepseek", expectedModel: "deepseek-v4-flash"),
                tts: .cloud(.cloudOpenAI, keyAccount: "byok.tts.openai", expectedModel: "gpt-4o-mini-tts")),
        ]

        for scenario in scenarios {
            resetToStaleCloudConfig()
            scenario.apply(to: defaults)
            let dispatcher = ProviderConfigDispatcher(defaults: defaults, keyReader: Self.keyReader)

            assertASR(scenario.asr, dispatcher: dispatcher, label: scenario.name)
            assertLLM(scenario.llm, dispatcher: dispatcher, label: scenario.name)
            try assertTTS(scenario.tts, label: scenario.name)
        }
    }

    func testLocalTTSSelectionDoesNotConsultKeysEvenWithStaleCloudConfig() throws {
        defaults.set(TTSEngine.sherpaKokoroLocal.rawValue, forKey: TTSEngine.defaultsKey)
        defaults.set("openai", forKey: "byok.tts.provider")

        var readAccounts: [String] = []
        let streaming = try TTSEngine.selected(defaults: defaults).makeStreamingSynthesizer(
            defaults: defaults,
            keyReader: { account in
                readAccounts.append(account)
                return "should-not-be-read"
            })

        XCTAssertNil(streaming)
        XCTAssertTrue(readAccounts.isEmpty)
    }

    func testCloudTTSDoesNotBorrowSharedASRLLMKeyWhenDedicatedKeyIsMissing() {
        for (engine, providerId) in [(TTSEngine.cloudQwen, "qwen"), (.cloudMimo, "mimo"), (.cloudOpenAI, "openai")] {
            let name = "test.crossCapabilityRoutingMatrix.tts.\(providerId)"
            let d = UserDefaults(suiteName: name)!
            d.removePersistentDomain(forName: name)
            ModelRouteSelectionActions.applyTTSSelection(engine.rawValue, defaults: d)

            XCTAssertThrowsError(
                try engine.makeSynthesizer(
                    defaults: d,
                    session: StubURLProtocol.session(),
                    keyReader: { account in
                        account == TTSCredential.coachAccount(for: providerId) ? "shared-key" : nil
                    })
            )
        }
    }

    func testQuickSelectionKeepsOneProviderScopedProfilePerCapability() throws {
        ModelRouteSelectionActions.applyASRSelection(
            ASREngine.cloudOpenAI.rawValue,
            defaults: defaults)
        ModelRouteSelectionActions.applyLLMSelection("deepseek", defaults: defaults)
        ModelRouteSelectionActions.applyTTSSelection(
            TTSEngine.cloudOpenAI.rawValue,
            defaults: defaults)

        for capability in [ModelCapability.asr, .llm, .tts] {
            for suffix in ["region", "plan", "model", "voice", "baseURL"] {
                XCTAssertNil(
                    defaults.object(forKey: "byok.\(capability.rawValue).\(suffix)"),
                    "\(capability.rawValue) still writes the obsolete active \(suffix) mirror")
            }
        }

        let dispatcher = ProviderConfigDispatcher(defaults: defaults, keyReader: Self.keyReader)
        let asr = dispatcher.resolve(.asr)
        XCTAssertEqual(ASREngine.selected(defaults: defaults), .cloudOpenAI)
        XCTAssertEqual(asr.providerId, "openai")
        XCTAssertEqual(asr.model, "gpt-4o-transcribe")
        XCTAssertEqual(asr.apiKey, "asr-openai-key")

        let llm = try XCTUnwrap(
            LLMEndpointResolver.resolveText(defaults: defaults, dispatcher: dispatcher))
        XCTAssertEqual(llm.providerId, "deepseek")
        XCTAssertEqual(llm.model, "deepseek-v4-flash")
        XCTAssertEqual(llm.apiKey, "llm-deepseek-key")

        let tts = try XCTUnwrap(
            TTSEngine.selected(defaults: defaults).makeSynthesizer(
                defaults: defaults,
                session: StubURLProtocol.session(),
                keyReader: Self.keyReader) as? DirectCloudTTSEngine)
        XCTAssertEqual(tts.model, "gpt-4o-mini-tts")
        XCTAssertEqual(tts.key, "tts-openai-key")
    }

    private func resetToStaleCloudConfig() {
        defaults.removePersistentDomain(forName: suite)
        ModelRouteSelectionActions.applyASRSelection(
            ASREngine.cloudOpenAI.rawValue,
            defaults: defaults)
        ModelRouteSelectionActions.applyLLMSelection("deepseek", defaults: defaults)
        ModelRouteSelectionActions.applyTTSSelection(
            TTSEngine.cloudOpenAI.rawValue,
            defaults: defaults)
    }

    private static func keyReader(_ account: String) -> String? {
        keys[account]
    }

    private func assertASR(_ route: ASRRoute, dispatcher: ProviderConfigDispatcher, label: String) {
        XCTAssertEqual(ASREngine.selected(defaults: defaults), route.engine, label)
        switch route {
        case .local(let engine):
            XCTAssertNil(engine.associatedProviderId, label)
        case .cloud(_, let providerId, let keyAccount, let expectedModel):
            let cfg = dispatcher.resolve(.asr, providerId: providerId)
            XCTAssertEqual(cfg.providerId, providerId, label)
            XCTAssertEqual(cfg.model, expectedModel, label)
            XCTAssertEqual(cfg.apiKey, Self.keyReader(keyAccount), label)
            XCTAssertFalse(cfg.baseURL.contains("localhost"), label)
        }
    }

    private func assertLLM(_ route: LLMRoute, dispatcher: ProviderConfigDispatcher, label: String) {
        let endpoint = LLMEndpointResolver.resolveText(defaults: defaults, dispatcher: dispatcher)
        switch route {
        case .cloud(let providerId, let keyAccount, let expectedModel):
            XCTAssertEqual(endpoint?.providerId, providerId, label)
            XCTAssertEqual(endpoint?.model, expectedModel, label)
            XCTAssertEqual(endpoint?.apiKey, Self.keyReader(keyAccount), label)
            XCTAssertFalse(endpoint?.isLocal ?? true, label)
        }
        XCTAssertTrue(endpoint?.isConfigured ?? false, label)
    }

    private func assertTTS(_ route: TTSRoute, label: String) throws {
        XCTAssertEqual(TTSEngine.selected(defaults: defaults), route.engine, label)
        switch route {
        case .local(let engine):
            XCTAssertNil(engine.providerID, label)
        case .cloud(let engine, let keyAccount, let expectedModel):
            let synth = try engine.makeSynthesizer(
                defaults: defaults,
                session: StubURLProtocol.session(),
                keyReader: Self.keyReader)
            if engine == .cloudQwen {
                let qwen = try XCTUnwrap(synth as? QwenStreamingTTSEngine)
                XCTAssertEqual(qwen.model, expectedModel, label)
                XCTAssertEqual(qwen.key, Self.keyReader(keyAccount), label)
                return
            }
            let cloud = try XCTUnwrap(synth as? DirectCloudTTSEngine)
            XCTAssertEqual(cloud.model, expectedModel, label)
            XCTAssertEqual(cloud.key, Self.keyReader(keyAccount), label)
        }
    }

    private struct Scenario {
        let name: String
        let asr: ASRRoute
        let llm: LLMRoute
        let tts: TTSRoute

        func apply(to defaults: UserDefaults) {
            ModelRouteSelectionActions.applyASRSelection(asr.engine.rawValue, defaults: defaults)

            switch llm {
            case .cloud(let providerId, _, _):
                ModelRouteSelectionActions.applyLLMSelection(providerId, defaults: defaults)
            }

            ModelRouteSelectionActions.applyTTSSelection(tts.engine.rawValue, defaults: defaults)
        }
    }

    private enum ASRRoute {
        case local(ASREngine)
        case cloud(ASREngine, providerId: String, keyAccount: String, expectedModel: String)

        var engine: ASREngine {
            switch self {
            case .local(let engine), .cloud(let engine, _, _, _): engine
            }
        }
    }

    private enum LLMRoute {
        case cloud(String, keyAccount: String, expectedModel: String)
    }

    private enum TTSRoute {
        case local(TTSEngine)
        case cloud(TTSEngine, keyAccount: String, expectedModel: String)

        var engine: TTSEngine {
            switch self {
            case .local(let engine), .cloud(let engine, _, _): engine
            }
        }
    }
}
