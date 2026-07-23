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

    func testQwenRealtimeUsesOnlyCurrentSettingsSlot() {
        XCTAssertEqual(
            ASRTranscriptionClientFactory.qwenASRFlashAPIKey(keyReader: { account in
                account == "byok.qwen-asr-flash" ? " settings-qwen-key " : nil
            }),
            "settings-qwen-key")
        XCTAssertEqual(
            ASRTranscriptionClientFactory.qwenASRFlashAPIKey(keyReader: { account in
                account == "byok.qwen-fun-asr" ? "retired-key" : nil
            }),
            "")
    }
}
