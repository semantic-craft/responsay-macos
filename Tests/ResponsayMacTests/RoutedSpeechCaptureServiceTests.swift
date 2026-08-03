import ResponsayCore
import XCTest
@testable import ResponsayMac

private final class ASRRuntimeStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responseData = Data()
    nonisolated(unsafe) static var requestURL: URL?
    nonisolated(unsafe) static var requestHeaders: [String: String] = [:]
    nonisolated(unsafe) static var requestBody = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requestURL = request.url
        Self.requestHeaders = request.allHTTPHeaderFields ?? [:]
        Self.requestBody = request.httpBody ?? Self.readBodyStream(request.httpBodyStream)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ASRRuntimeStubURLProtocol.self]
        return URLSession(configuration: config)
    }

    static func reset(responseData: Data) {
        Self.responseData = responseData
        requestURL = nil
        requestHeaders = [:]
        requestBody = Data()
    }

    private static func readBodyStream(_ stream: InputStream?) -> Data {
        guard let stream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

/// 猎虫① H11 (issue 322): the router never conformed to
/// `SpeechPartialTranscriptProviding`, so the `as?` casts in
/// QuickCaptureViewModel / VoiceAssistantViewModel always failed — live capsule
/// preview and streaming ASR direct-write were dead for every engine in
/// production, while tests passed by injecting conforming mocks directly.
/// These tests pin the conformance at the router seam itself.
final class RoutedSpeechCaptureServiceTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "routed-asr-runtime-tests"

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

    @MainActor
    func testRouterProvidesPartialTranscripts() {
        let router: SpeechCaptureService = RoutedSpeechCaptureService()
        XCTAssertNotNil(
            router as? SpeechPartialTranscriptProviding,
            "router must forward partials or the VM-side streaming path is dead for all engines")
    }

    @MainActor
    func testPartialStreamWithoutActiveCaptureFinishesImmediately() async {
        let router = RoutedSpeechCaptureService()
        var received = [String]()
        // No capture started → the fallback stream must finish at once
        // (a hang here would wedge the VM's partial task).
        for await text in router.partialTranscripts {
            received.append(text)
        }
        XCTAssertTrue(received.isEmpty)
    }

    func testSettingsBackedOpenAIClientUsesCapabilityCardSlot() async throws {
        defaults.set("openai", forKey: "byok.asr.provider")
        defaults.set("https://asr.proxy.test/v1", forKey: "byok.asr.baseURL")
        defaults.set("gpt-4o-transcribe", forKey: "byok.asr.model")
        ASRRuntimeStubURLProtocol.reset(responseData: #"{"text":"ok"}"#.data(using: .utf8)!)

        let client = ASRTranscriptionClientFactory.openAI(
            defaults: defaults,
            session: ASRRuntimeStubURLProtocol.session(),
            keyReader: { $0 == "byok.openai" ? "settings-openai-key" : nil })

        let result = try await client.transcribe(
            audio: Data([0x01]),
            mimeType: "audio/wav",
            language: "en")

        XCTAssertEqual(ASRRuntimeStubURLProtocol.requestURL?.absoluteString,
                       "https://asr.proxy.test/v1/audio/transcriptions")
        XCTAssertEqual(ASRRuntimeStubURLProtocol.requestHeaders["Authorization"],
                       "Bearer settings-openai-key")
        XCTAssertEqual(result.model, "gpt-4o-transcribe")
    }

    func testSettingsBackedMimoClientUsesCatalogProviderIdAndSlot() async throws {
        defaults.set("mimo", forKey: "byok.asr.provider")
        defaults.set("https://mimo.proxy.test/v1", forKey: "byok.asr.baseURL")
        defaults.set("mimo-custom-asr", forKey: "byok.asr.model")
        ASRRuntimeStubURLProtocol.reset(
            responseData: #"{"choices":[{"message":{"content":"ok"}}]}"#.data(using: .utf8)!)

        let client = ASRTranscriptionClientFactory.mimo(
            defaults: defaults,
            session: ASRRuntimeStubURLProtocol.session(),
            keyReader: { $0 == CapabilityCredentialAccount.apiKeyAccount(
                providerId: "mimo", capability: .asr, plan: .package) ? "settings-mimo-key" : nil })

        let result = try await client.transcribe(
            audio: Data([0x01]),
            mimeType: "audio/wav",
            language: "zh")

        let body = String(decoding: ASRRuntimeStubURLProtocol.requestBody, as: UTF8.self)
        XCTAssertEqual(ASRRuntimeStubURLProtocol.requestURL?.absoluteString,
                       "https://mimo.proxy.test/v1/chat/completions")
        XCTAssertEqual(ASRRuntimeStubURLProtocol.requestHeaders["api-key"],
                       "settings-mimo-key")
        XCTAssertNil(ASRRuntimeStubURLProtocol.requestHeaders["Authorization"])
        XCTAssertTrue(body.contains("mimo-custom-asr"))
        XCTAssertEqual(result.provider, "mimo")
    }

    func testSettingsBackedMimoClientDefaultsToTokenPlanEndpoint() async throws {
        defaults.set("mimo", forKey: "byok.asr.provider")
        ASRRuntimeStubURLProtocol.reset(
            responseData: #"{"choices":[{"message":{"content":"ok"}}]}"#.data(using: .utf8)!)

        let client = ASRTranscriptionClientFactory.mimo(
            defaults: defaults,
            session: ASRRuntimeStubURLProtocol.session(),
            keyReader: { $0 == CapabilityCredentialAccount.apiKeyAccount(
                providerId: "mimo", capability: .asr, plan: .package) ? "settings-mimo-key" : nil })

        _ = try await client.transcribe(
            audio: Data([0x01]),
            mimeType: "audio/wav",
            language: "zh")

        XCTAssertEqual(ASRRuntimeStubURLProtocol.requestURL?.absoluteString,
                       "https://token-plan-cn.xiaomimimo.com/v1/chat/completions")
    }

    /// The 千问 card dials the run-task socket. Without a Workspace ID it must keep using the
    /// generic DashScope host, and it must read only the current `byok.qwen-asr-flash` slot.
    func testQwenRunTaskWithoutWorkspaceUsesGenericHostAndCurrentKeySlot() {
        defaults.set("qwen-asr-flash", forKey: "byok.asr.provider")

        let config = ASRTranscriptionClientFactory.qwenRunTaskConfig(
            defaults: defaults,
            keyReader: { $0 == "byok.qwen-asr-flash" ? " settings-qwen-key " : nil })

        XCTAssertEqual(config.endpoint.url.absoluteString,
                       "wss://dashscope.aliyuncs.com/api-ws/v1/inference")
        XCTAssertFalse(config.endpoint.usesDedicatedHost)
        XCTAssertEqual(config.apiKey, "settings-qwen-key")
        XCTAssertEqual(config.model, "qwen-audio-3.0-asr-flash-streaming")
    }

    func testQwenRunTaskUsesFreshPrecompiledVocabularyBinding() {
        defaults.set("qwen-asr-flash", forKey: "byok.asr.provider")
        XCTAssertTrue(ContextHotwordSettings.addManual("Westlaw", defaults: defaults))
        QwenPrecompiledVocabularySettings.save(
            identifier: "vocab-curated-a1b2c3",
            model: QwenRunTaskEndpoint.defaultModel,
            endpoint: QwenRunTaskEndpoint(region: .china),
            vocabularyTerms: ContextHotwordSettings.qwenPersistentHotwords(defaults: defaults),
            defaults: defaults)

        let config = ASRTranscriptionClientFactory.qwenRunTaskConfig(
            defaults: defaults, keyReader: { _ in "k" })

        XCTAssertEqual(config.precompiledVocabularyID, "vocab-curated-a1b2c3")
        XCTAssertTrue(config.hotwords.isEmpty)
    }

    func testQwenRunTaskFallsBackToFullInstantVocabularyAfterLearningMixedTerm() {
        defaults.set("qwen-asr-flash", forKey: "byok.asr.provider")
        XCTAssertTrue(ContextHotwordSettings.addManual("Westlaw", defaults: defaults))
        QwenPrecompiledVocabularySettings.save(
            identifier: "vocab-curated-a1b2c3",
            model: QwenRunTaskEndpoint.defaultModel,
            endpoint: QwenRunTaskEndpoint(region: .china),
            vocabularyTerms: ContextHotwordSettings.qwenPersistentHotwords(defaults: defaults),
            defaults: defaults)
        XCTAssertTrue(ContextHotwordSettings.addAuto("法研 Metis", defaults: defaults))

        let config = ASRTranscriptionClientFactory.qwenRunTaskConfig(
            defaults: defaults, keyReader: { _ in "k" })

        XCTAssertNil(config.precompiledVocabularyID)
        XCTAssertEqual(Set(config.hotwords), ["Westlaw", "法研 Metis"])
    }

    func testQwenRunTaskMalformedBindingFailsOpenWithoutExposingItInConfig() {
        defaults.set("qwen-asr-flash", forKey: "byok.asr.provider")
        defaults.set("Metis", forKey: ContextHotwordSettings.defaultsKey)
        defaults.set("not-json", forKey: QwenPrecompiledVocabularySettings.scopedDefaultsKey)

        let config = ASRTranscriptionClientFactory.qwenRunTaskConfig(
            defaults: defaults, keyReader: { _ in "k" })

        XCTAssertNil(config.precompiledVocabularyID)
        XCTAssertEqual(config.hotwords, ["Metis"])
    }

    func testQwenRunTaskSingaporeWorkspaceOmitsAllUnsupportedVocabulary() {
        defaults.set("qwen-asr-flash", forKey: "byok.asr.provider")
        defaults.set("singapore", forKey: "byok.asr.region")
        defaults.set("ws-abc123", forKey: "byok.asr.qwen-asr-flash.workspaceId")
        XCTAssertTrue(ContextHotwordSettings.addManual("法研 Metis", defaults: defaults))
        XCTAssertNil(QwenPrecompiledVocabularySettings.save(
            identifier: "vocab-deadbeef",
            model: QwenRunTaskEndpoint.defaultModel,
            endpoint: QwenRunTaskEndpoint(region: .singapore, workspaceID: "ws-abc123"),
            vocabularyTerms: ContextHotwordSettings.qwenPersistentHotwords(defaults: defaults),
            defaults: defaults))

        let config = ASRTranscriptionClientFactory.qwenRunTaskConfig(
            defaults: defaults, keyReader: { _ in "k" })

        XCTAssertFalse(config.endpoint.supportsHotwords)
        XCTAssertNil(config.precompiledVocabularyID)
        XCTAssertTrue(config.hotwords.isEmpty)
    }

    func testQwenRunTaskPreservesHeartbeatAndProviderVADDefaults() {
        defaults.set("qwen-asr-flash", forKey: "byok.asr.provider")

        let config = ASRTranscriptionClientFactory.qwenRunTaskConfig(
            defaults: defaults, keyReader: { _ in "k" })
        XCTAssertTrue(config.heartbeat)
    }

    /// Filling in a Workspace ID switches the socket onto that business space's dedicated host.
    func testQwenRunTaskWorkspaceIDDerivesDedicatedHost() {
        defaults.set("qwen-asr-flash", forKey: "byok.asr.provider")
        defaults.set("ws-abc123", forKey: "byok.asr.qwen-asr-flash.workspaceId")

        let config = ASRTranscriptionClientFactory.qwenRunTaskConfig(
            defaults: defaults,
            keyReader: { $0 == "byok.qwen-asr-flash" ? "settings-qwen-key" : nil })

        XCTAssertTrue(config.endpoint.usesDedicatedHost)
        XCTAssertEqual(config.endpoint.url.absoluteString,
                       "wss://ws-abc123.cn-beijing.maas.aliyuncs.com/api-ws/v1/inference")
    }

    /// 新加坡 switches both the generic and the dedicated host.
    func testQwenRunTaskSingaporeRegionSwitchesHost() {
        defaults.set("qwen-asr-flash", forKey: "byok.asr.provider")
        defaults.set("singapore", forKey: "byok.asr.region")

        XCTAssertEqual(
            ASRTranscriptionClientFactory.qwenRunTaskConfig(defaults: defaults, keyReader: { _ in "k" })
                .endpoint.url.absoluteString,
            "wss://dashscope-intl.aliyuncs.com/api-ws/v1/inference")

        defaults.set("ws-abc123", forKey: "byok.asr.qwen-asr-flash.workspaceId")
        XCTAssertEqual(
            ASRTranscriptionClientFactory.qwenRunTaskConfig(defaults: defaults, keyReader: { _ in "k" })
                .endpoint.url.absoluteString,
            "wss://ws-abc123.ap-southeast-1.maas.aliyuncs.com/api-ws/v1/inference")
    }

    /// An install carried over from the retired OmniRealtime engine still has that endpoint and a
    /// `qwen3-asr-flash-realtime-*` model under these keys — a different protocol on a sibling path,
    /// and the one Qwen realtime model with no hotword support. Neither may reach the socket.
    func testQwenRunTaskDropsRetiredOmniRealtimeEndpointAndModel() {
        defaults.set("qwen-asr-flash", forKey: "byok.asr.provider")
        defaults.set("wss://dashscope.aliyuncs.com/api-ws/v1/realtime", forKey: "byok.asr.baseURL")
        defaults.set("qwen3-asr-flash-realtime-2026-02-10", forKey: "byok.asr.model")

        let config = ASRTranscriptionClientFactory.qwenRunTaskConfig(
            defaults: defaults, keyReader: { _ in "settings-qwen-key" })

        XCTAssertEqual(config.endpoint.url.absoluteString,
                       "wss://dashscope.aliyuncs.com/api-ws/v1/inference")
        XCTAssertEqual(config.model, "qwen-audio-3.0-asr-flash-streaming")
    }

    /// A model the user picked from the card's dropdown must survive.
    func testQwenRunTaskKeepsUserPickedFunASRRealtimeModel() {
        defaults.set("qwen-asr-flash", forKey: "byok.asr.provider")
        defaults.set("fun-asr-realtime", forKey: "byok.asr.model")

        XCTAssertEqual(
            ASRTranscriptionClientFactory.qwenRunTaskConfig(defaults: defaults, keyReader: { _ in "k" }).model,
            "fun-asr-realtime")
    }
}
