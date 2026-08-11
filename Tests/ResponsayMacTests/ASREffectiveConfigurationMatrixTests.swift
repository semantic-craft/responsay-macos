import AVFoundation
import Foundation
@testable import ResponsayCore
@testable import ResponsaySpeech
import XCTest
@testable import ResponsayMac

private final class EffectiveASRStubURLProtocol: URLProtocol {
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
            headerFields: [
                "Content-Type": request.value(forHTTPHeaderField: "Accept") == "text/event-stream"
                    ? "text/event-stream"
                    : "application/json",
            ])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readBodyStream(_ stream: InputStream?) -> Data {
        guard let stream else { return Data() }
        stream.open()
        defer { stream.close() }
        var body = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            body.append(contentsOf: buffer.prefix(count))
        }
        return body
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EffectiveASRStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func reset(responseData: Data) {
        self.responseData = responseData
        requestURL = nil
        requestHeaders = [:]
        requestBody = Data()
    }
}

private final class EffectiveASRWebSocketTaskFactory: @unchecked Sendable {
    private let requestLock = NSLock()
    private var capturedRequest: URLRequest?
    private let backingSession = URLSession(configuration: .ephemeral)

    func make(request: URLRequest) -> URLSessionWebSocketTask {
        requestLock.withLock { capturedRequest = request }
        var localRequest = request
        localRequest.url = URL(string: "ws://127.0.0.1:1")!
        return backingSession.webSocketTask(with: localRequest)
    }

    var request: URLRequest? { requestLock.withLock { capturedRequest } }
}

private final class EffectiveASRCredentialStore: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    private var reads: [String] = []

    func read(_ account: String) -> String? {
        lock.withLock {
            reads.append(account)
            return values[account]
        }
    }

    func write(_ value: String, account: String) {
        lock.withLock {
            values[account] = value
        }
    }

    func resetReads() {
        lock.withLock {
            reads = []
        }
    }

    var recordedReads: [String] {
        lock.withLock { reads }
    }
}

private final class EffectiveASRLocalAudioRecorder: @unchecked Sendable, SpeechAudioRecording {
    private let lock = NSLock()
    private var onBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?

    func start(
        preferredUID _: String,
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void
    ) throws {
        lock.withLock { self.onBuffer = onBuffer }
    }

    func stop() {
        lock.withLock { onBuffer = nil }
    }

    func deliverSpeech() {
        let samples = Array(repeating: Float(0.1), count: 7_000)
        let format = AVCaptureAudioRecorder.deliveredFormat
        let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for (index, sample) in samples.enumerated() {
            buffer.floatChannelData![0][index] = sample
        }
        lock.withLock { onBuffer }?(buffer)
    }
}

private struct EffectiveASRMatrixCase {
    enum Runtime {
        case openAI
        case mimo
        case gemini
        case volcengine
        case custom
    }

    let name: String
    let runtime: Runtime
    let engine: ASREngine
    let providerID: String
    let region: ProviderRegion
    let plan: BillingPlan
    let persistedBaseURL: String
    let persistedModel: String
    let expectedBaseURL: String
    let expectedModel: String
    let credential: String
    let expectedRequestURL: String?
    let expectedHeader: (name: String, value: String)?
}

final class ASREffectiveConfigurationMatrixTests: XCTestCase {
    private var defaults: UserDefaults!
    private var credentials: EffectiveASRCredentialStore!
    private let suite = "asr-effective-configuration-matrix-tests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
        credentials = EffectiveASRCredentialStore()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        credentials = nil
        defaults = nil
        super.tearDown()
    }

    @MainActor
    func testPersistedCloudProviderMatrixReachesOneCaptureSnapshotWithoutSwitchLeakage() async throws {
        let cases = matrixCases()

        for (index, testCase) in cases.enumerated() {
            guard case .volcengine = testCase.runtime else {
                let nextCase = cases[(index + 1) % cases.count]
                persist(testCase)
                credentials.resetReads()
                let recorder = EffectiveASRLocalAudioRecorder()
                EffectiveASRStubURLProtocol.reset(
                    responseData: routerResponseData(for: testCase.runtime))
                let router = makeRouter(
                    recorder: recorder,
                    session: EffectiveASRStubURLProtocol.session())

                try router.start(locale: .chinese)
                assertOnlyCredentialRead(for: testCase)

                // A settings change while recording must affect only the next capture. The client
                // was resolved by the production router at `start`, so endpoint, model and key stay
                // one immutable tuple through the upload performed by `stop`.
                persist(nextCase)
                recorder.deliverSpeech()
                let transcript = try await router.stop()

                XCTAssertEqual(transcript, "ok", testCase.name)
                XCTAssertEqual(
                    EffectiveASRStubURLProtocol.requestURL?.absoluteString,
                    testCase.expectedRequestURL,
                    testCase.name)
                if let expectedHeader = testCase.expectedHeader {
                    XCTAssertEqual(
                        EffectiveASRStubURLProtocol.requestHeaders[expectedHeader.name],
                        expectedHeader.value,
                        testCase.name)
                }
                let requestBody = String(
                    decoding: EffectiveASRStubURLProtocol.requestBody,
                    as: UTF8.self)
                let requestWire = (EffectiveASRStubURLProtocol.requestURL?.absoluteString ?? "")
                    + requestBody
                XCTAssertTrue(requestWire.contains(testCase.expectedModel), testCase.name)
                XCTAssertFalse(requestWire.contains(nextCase.expectedModel), testCase.name)
                continue
            }

            // Volcengine uses a WebSocket rather than URLSession.data. The production client is
            // still constructed by the router; the session double records the original upgrade
            // request and redirects only the external transport to a closed loopback port.
            persist(testCase)
            credentials.resetReads()
            let recorder = EffectiveASRLocalAudioRecorder()
            let webSocketTaskFactory = EffectiveASRWebSocketTaskFactory()
            let router = makeRouter(
                recorder: recorder,
                session: .shared,
                webSocketTaskProvider: { webSocketTaskFactory.make(request: $0) })

            try router.start(locale: .chinese)
            assertOnlyCredentialRead(for: testCase)
            let nextCase = cases[(index + 1) % cases.count]
            persist(nextCase)
            recorder.deliverSpeech()
            do {
                _ = try await router.stop()
                XCTFail("Volcengine loopback transport must fail", file: #filePath, line: #line)
            } catch {
                // Expected: no provider network request is made by this offline construction test.
            }
            let request = try XCTUnwrap(webSocketTaskFactory.request, testCase.name)
            XCTAssertEqual(request.url?.host, "openspeech.bytedance.com", testCase.name)
            XCTAssertEqual(
                request.url?.path,
                "/api/v3/sauc/bigmodel_nostream",
                testCase.name)
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "X-Api-Key"),
                testCase.credential,
                testCase.name)
            XCTAssertNotEqual(
                request.value(forHTTPHeaderField: "X-Api-Key"),
                nextCase.credential,
                testCase.name)
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "X-Api-Resource-Id"),
                "volc.seedasr.sauc.duration",
                testCase.name)
        }
    }

    @MainActor
    func testMiMoPackageToPaygSwitchResolvesOneEndpointPlanCredentialTuple() async throws {
        ModelRouteSelectionActions.applyASRSelection(ASREngine.cloudMimo.rawValue, defaults: defaults)
        let packageMachine = ProviderConfigMachine(
            capability: .asr,
            preferredProviderId: "mimo",
            defaults: defaults,
            keyReader: { [credentials] in credentials?.read($0) },
            keyWriter: { [credentials] in credentials?.write($0, account: $1) })
        packageMachine.load()
        packageMachine.regionRaw = ProviderRegion.singapore.rawValue
        packageMachine.planRaw = BillingPlan.package.rawValue
        packageMachine.baseURL = "https://token-plan-sgp.xiaomimimo.com/v1"
        packageMachine.model = "mimo-package-model"
        packageMachine.apiKey = "mimo-package-key"
        packageMachine.writeApiKey()
        packageMachine.persist()

        let packageRecorder = EffectiveASRLocalAudioRecorder()
        EffectiveASRStubURLProtocol.reset(responseData: routerResponseData(for: .mimo))
        let packageRouter = makeRouter(
            recorder: packageRecorder,
            session: EffectiveASRStubURLProtocol.session())
        try packageRouter.start(locale: .chinese)

        // Switch through the production quick-selection action. PAYG has no Singapore endpoint,
        // so the persisted selection itself must move to the complete China PAYG tuple instead of
        // retaining the Singapore Token Plan URL and pairing it with the PAYG key.
        credentials.write(
            "mimo-payg-key",
            account: CapabilityCredentialAccount.apiKeyAccount(
                providerId: "mimo", capability: .asr, plan: .payg))
        ModelRouteSelectionActions.applyASRSelection("cloud-mimo#payg", defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: "byok.asr.mimo.region"), ProviderRegion.china.rawValue)
        XCTAssertEqual(defaults.string(forKey: "byok.asr.mimo.plan"), BillingPlan.payg.rawValue)
        XCTAssertEqual(
            defaults.string(forKey: "byok.asr.mimo.baseURL"),
            "https://api.xiaomimimo.com/v1")

        // Runtime resolution remains safe if a stale Token Plan URL survives with an equivalent
        // trailing-slash spelling that does not byte-match the catalog value.
        CapabilityProviderConfigStore.set(
            "https://token-plan-sgp.xiaomimimo.com/v1/",
            suffix: "baseURL",
            providerId: "mimo",
            capability: .asr,
            defaults: defaults)

        let effective = ProviderConfigDispatcher(
            defaults: defaults,
            keyReader: { [credentials] in credentials?.read($0) })
            .resolve(.asr, providerId: "mimo")
        XCTAssertEqual(effective.region, .china)
        XCTAssertEqual(effective.plan, .payg)
        XCTAssertEqual(effective.baseURL, "https://api.xiaomimimo.com/v1")
        XCTAssertEqual(effective.apiKey, "mimo-payg-key")

        packageRecorder.deliverSpeech()
        let packageTranscript = try await packageRouter.stop()
        XCTAssertEqual(packageTranscript, "ok")
        XCTAssertEqual(
            EffectiveASRStubURLProtocol.requestURL?.absoluteString,
            "https://token-plan-sgp.xiaomimimo.com/v1/chat/completions")
        XCTAssertEqual(EffectiveASRStubURLProtocol.requestHeaders["api-key"], "mimo-package-key")

        let paygRecorder = EffectiveASRLocalAudioRecorder()
        EffectiveASRStubURLProtocol.reset(responseData: routerResponseData(for: .mimo))
        let paygRouter = makeRouter(
            recorder: paygRecorder,
            session: EffectiveASRStubURLProtocol.session())
        try paygRouter.start(locale: .chinese)
        paygRecorder.deliverSpeech()
        let paygTranscript = try await paygRouter.stop()
        XCTAssertEqual(paygTranscript, "ok")
        XCTAssertEqual(
            EffectiveASRStubURLProtocol.requestURL?.absoluteString,
            "https://api.xiaomimimo.com/v1/chat/completions")
        XCTAssertEqual(EffectiveASRStubURLProtocol.requestHeaders["api-key"], "mimo-payg-key")
    }

    @MainActor
    func testMiMoDoesNotEchoFilterDictionaryTermsItNeverSends() async throws {
        let testCase = matrixCases().first { testCase in
            if case .mimo = testCase.runtime { return testCase.plan == .payg }
            return false
        }!
        persist(testCase)
        defaults.set("Westlaw, SSRN", forKey: ContextHotwordSettings.defaultsKey)
        let recorder = EffectiveASRLocalAudioRecorder()
        EffectiveASRStubURLProtocol.reset(responseData: mimoResponseData(text: "Westlaw, SSRN"))
        let router = makeRouter(
            recorder: recorder,
            session: EffectiveASRStubURLProtocol.session())

        try router.start(locale: .chinese)
        recorder.deliverSpeech()
        let transcript = try await router.stop()

        XCTAssertEqual(transcript, "Westlaw, SSRN")
    }

    private func matrixCases() -> [EffectiveASRMatrixCase] {
        [
            EffectiveASRMatrixCase(
                name: "OpenAI",
                runtime: .openAI,
                engine: .cloudOpenAI,
                providerID: "openai",
                region: .global,
                plan: .payg,
                persistedBaseURL: "https://openai-asr.test/v1",
                persistedModel: "openai-selected-model",
                expectedBaseURL: "https://openai-asr.test/v1",
                expectedModel: "openai-selected-model",
                credential: "openai-selected-key",
                expectedRequestURL: "https://openai-asr.test/v1/audio/transcriptions",
                expectedHeader: ("Authorization", "Bearer openai-selected-key")),
            EffectiveASRMatrixCase(
                name: "MiMo PAYG",
                runtime: .mimo,
                engine: .cloudMimo,
                providerID: "mimo",
                region: .china,
                plan: .payg,
                persistedBaseURL: "https://api.xiaomimimo.com/v1",
                persistedModel: "mimo-payg-selected-model",
                expectedBaseURL: "https://api.xiaomimimo.com/v1",
                expectedModel: "mimo-payg-selected-model",
                credential: "mimo-payg-selected-key",
                expectedRequestURL: "https://api.xiaomimimo.com/v1/chat/completions",
                expectedHeader: ("api-key", "mimo-payg-selected-key")),
            EffectiveASRMatrixCase(
                name: "MiMo Token Plan",
                runtime: .mimo,
                engine: .cloudMimo,
                providerID: "mimo",
                region: .singapore,
                plan: .package,
                persistedBaseURL: "https://token-plan-sgp.xiaomimimo.com/v1",
                persistedModel: "mimo-package-selected-model",
                expectedBaseURL: "https://token-plan-sgp.xiaomimimo.com/v1",
                expectedModel: "mimo-package-selected-model",
                credential: "mimo-package-selected-key",
                expectedRequestURL: "https://token-plan-sgp.xiaomimimo.com/v1/chat/completions",
                expectedHeader: ("api-key", "mimo-package-selected-key")),
            EffectiveASRMatrixCase(
                name: "Gemini",
                runtime: .gemini,
                engine: .cloudGemini,
                providerID: "gemini",
                region: .global,
                plan: .payg,
                persistedBaseURL: "https://gemini-asr.test/v1beta/",
                persistedModel: "gemini-selected-model",
                expectedBaseURL: "https://gemini-asr.test/v1beta/",
                expectedModel: "gemini-selected-model",
                credential: "gemini-selected-key",
                expectedRequestURL: "https://gemini-asr.test/v1beta/models/gemini-selected-model:generateContent",
                expectedHeader: ("x-goog-api-key", "gemini-selected-key")),
            EffectiveASRMatrixCase(
                name: "Volcengine fixed route",
                runtime: .volcengine,
                engine: .cloudVolcengineRealtime,
                providerID: "volcengine-flash",
                region: .china,
                plan: .payg,
                persistedBaseURL: "https://stale-volcengine.test/v1",
                persistedModel: "stale-volcengine-model",
                expectedBaseURL: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_nostream",
                expectedModel: "bigmodel",
                credential: "volcengine-selected-key",
                expectedRequestURL: nil,
                expectedHeader: nil),
            EffectiveASRMatrixCase(
                name: "Custom OpenAI-compatible",
                runtime: .custom,
                engine: .customOpenAI,
                providerID: "custom",
                region: .global,
                plan: .payg,
                persistedBaseURL: "https://custom-asr.test/v1",
                persistedModel: "custom-selected-model",
                expectedBaseURL: "https://custom-asr.test/v1",
                expectedModel: "custom-selected-model",
                credential: "custom-selected-key",
                expectedRequestURL: "https://custom-asr.test/v1/audio/transcriptions",
                expectedHeader: ("Authorization", "Bearer custom-selected-key")),
        ]
    }

    @MainActor
    private func makeRouter(
        recorder: EffectiveASRLocalAudioRecorder,
        session: URLSession,
        webSocketTaskProvider: (@Sendable (URLRequest) -> URLSessionWebSocketTask)? = nil
    ) -> RoutedSpeechCaptureService {
        let contextURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("router-matrix-\(UUID().uuidString).json")
        return RoutedSpeechCaptureService(
            contextScopeProvider: { nil },
            defaults: defaults,
            keyReader: { [credentials] in credentials?.read($0) },
            qwenRunTask: QwenRunTaskSession(),
            qwenAudioRecorder: { recorder },
            qwenContextStore: RecentASRContextSessionStore(
                defaults: defaults,
                fileURL: contextURL),
            requireQwenMicPermission: {},
            batchSession: session,
            batchWebSocketTask: webSocketTaskProvider,
            batchAudioRecorder: { recorder },
            requireBatchMicPermission: { _ in })
    }

    @MainActor
    private func persist(_ testCase: EffectiveASRMatrixCase) {
        ModelRouteSelectionActions.applyASRSelection(testCase.engine.rawValue, defaults: defaults)
        let machine = ProviderConfigMachine(
            capability: .asr,
            preferredProviderId: testCase.providerID,
            defaults: defaults,
            keyReader: { [credentials] in credentials?.read($0) },
            keyWriter: { [credentials] in credentials?.write($0, account: $1) })
        machine.load()
        machine.regionRaw = testCase.region.rawValue
        machine.planRaw = testCase.plan.rawValue
        machine.baseURL = testCase.persistedBaseURL
        machine.model = testCase.persistedModel
        machine.apiKey = testCase.credential
        machine.writeApiKey()
        machine.persist()

        let effective = ProviderConfigDispatcher(
            defaults: defaults,
            keyReader: { [credentials] in credentials?.read($0) })
            .resolve(.asr, providerId: testCase.providerID)
        XCTAssertEqual(effective.providerId, testCase.providerID, testCase.name)
        XCTAssertEqual(effective.region, testCase.region, testCase.name)
        XCTAssertEqual(effective.plan, testCase.plan, testCase.name)
        XCTAssertEqual(effective.baseURL, testCase.expectedBaseURL, testCase.name)
        XCTAssertEqual(effective.model, testCase.expectedModel, testCase.name)
        XCTAssertEqual(effective.apiKey, testCase.credential, testCase.name)
    }

    private func assertOnlyCredentialRead(for testCase: EffectiveASRMatrixCase) {
        let expectedAccount = CapabilityCredentialAccount.apiKeyAccount(
            providerId: testCase.providerID,
            capability: .asr,
            plan: testCase.plan)
        XCTAssertFalse(credentials.recordedReads.isEmpty, testCase.name)
        XCTAssertTrue(
            credentials.recordedReads.allSatisfy { $0 == expectedAccount },
            testCase.name)
    }

    private func routerResponseData(for runtime: EffectiveASRMatrixCase.Runtime) -> Data {
        let payload: String
        switch runtime {
        case .openAI, .custom:
            payload = #"{"text":"ok"}"#
        case .mimo:
            return mimoResponseData(text: "ok")
        case .gemini:
            payload = #"{"candidates":[{"content":{"parts":[{"text":"ok"}]}}]}"#
        case .volcengine:
            payload = "{}"
        }
        return Data(payload.utf8)
    }

    private func mimoResponseData(text: String) -> Data {
        Data("""
        data: {"choices":[{"delta":{"content":"\(text)","role":null},"finish_reason":null,"index":0}],"object":"chat.completion.chunk"}

        data: {"choices":[{"delta":{"content":null,"role":null},"finish_reason":"stop","index":0}],"object":"chat.completion.chunk"}

        data: [DONE]

        """.utf8)
    }
}
