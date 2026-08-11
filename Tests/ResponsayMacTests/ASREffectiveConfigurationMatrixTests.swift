import Foundation
@testable import ResponsayCore
import XCTest
@testable import ResponsayMac

private final class EffectiveASRStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responseData = Data()
    nonisolated(unsafe) static var requestURL: URL?
    nonisolated(unsafe) static var requestHeaders: [String: String] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestURL = request.url
        Self.requestHeaders = request.allHTTPHeaderFields ?? [:]
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
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EffectiveASRStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func reset(responseData: Data) {
        self.responseData = responseData
        requestURL = nil
        requestHeaders = [:]
    }
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

private enum BuiltEffectiveASRRuntime {
    case batch(any TranscriptionAPI)
    case volcengine(VolcengineRealtimeTranscriptionAPI)
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
        let cases = [
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

        for (index, testCase) in cases.enumerated() {
            let nextCase = cases[(index + 1) % cases.count]
            persist(testCase)
            credentials.resetReads()
            let runtime = buildRuntimeFromPersistedSelection(expected: testCase)
            assertOnlyCredentialRead(for: testCase)

            // The client is the capture-start snapshot. A settings change while recording must
            // only affect the next capture, never combine this capture's endpoint with the newly
            // selected provider's model, plan, or credential. The next capture is then built from
            // the newly persisted engine through the same route → factory seam production uses.
            persist(nextCase)
            credentials.resetReads()
            let nextRuntime = buildRuntimeFromPersistedSelection(expected: nextCase)
            assertOnlyCredentialRead(for: nextCase)

            try await assertRuntime(runtime, matches: testCase)
            try await assertRuntime(nextRuntime, matches: nextCase)
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

        let packageClient = ASRTranscriptionClientFactory.mimo(
            defaults: defaults,
            session: EffectiveASRStubURLProtocol.session(),
            keyReader: { [credentials] in credentials?.read($0) })

        // Switch through the production quick-selection action. PAYG has no Singapore endpoint,
        // so the persisted selection itself must move to the complete China PAYG tuple instead of
        // retaining the Singapore Token Plan URL and pairing it with the PAYG key.
        credentials.write(
            "mimo-payg-key",
            account: CapabilityCredentialAccount.apiKeyAccount(
                providerId: "mimo", capability: .asr, plan: .payg))
        ModelRouteSelectionActions.applyASRSelection("cloud-mimo#payg", defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: "byok.asr.region"), ProviderRegion.china.rawValue)
        XCTAssertEqual(defaults.string(forKey: "byok.asr.plan"), BillingPlan.payg.rawValue)
        XCTAssertEqual(defaults.string(forKey: "byok.asr.baseURL"), "https://api.xiaomimimo.com/v1")

        // Runtime resolution remains safe if a stale Token Plan URL survives with an equivalent
        // trailing-slash spelling that does not byte-match the catalog value.
        CapabilityProviderConfigStore.set(
            "https://token-plan-sgp.xiaomimimo.com/v1/",
            suffix: "baseURL",
            providerId: "mimo",
            capability: .asr,
            defaults: defaults,
            activeProviderId: "mimo")

        let effective = ProviderConfigDispatcher(
            defaults: defaults,
            keyReader: { [credentials] in credentials?.read($0) })
            .resolve(.asr, providerId: "mimo")
        XCTAssertEqual(effective.region, .china)
        XCTAssertEqual(effective.plan, .payg)
        XCTAssertEqual(effective.baseURL, "https://api.xiaomimimo.com/v1")
        XCTAssertEqual(effective.apiKey, "mimo-payg-key")

        let paygClient = ASRTranscriptionClientFactory.mimo(
            defaults: defaults,
            session: EffectiveASRStubURLProtocol.session(),
            keyReader: { [credentials] in credentials?.read($0) })

        EffectiveASRStubURLProtocol.reset(
            responseData: #"{"choices":[{"message":{"content":"ok"}}]}"#.data(using: .utf8)!)
        _ = try await packageClient.transcribe(audio: Data([0x01]), mimeType: "audio/wav", language: "zh")
        XCTAssertEqual(
            EffectiveASRStubURLProtocol.requestURL?.absoluteString,
            "https://token-plan-sgp.xiaomimimo.com/v1/chat/completions")
        XCTAssertEqual(EffectiveASRStubURLProtocol.requestHeaders["api-key"], "mimo-package-key")

        EffectiveASRStubURLProtocol.reset(
            responseData: #"{"choices":[{"message":{"content":"ok"}}]}"#.data(using: .utf8)!)
        _ = try await paygClient.transcribe(audio: Data([0x01]), mimeType: "audio/wav", language: "zh")
        XCTAssertEqual(
            EffectiveASRStubURLProtocol.requestURL?.absoluteString,
            "https://api.xiaomimimo.com/v1/chat/completions")
        XCTAssertEqual(EffectiveASRStubURLProtocol.requestHeaders["api-key"], "mimo-payg-key")
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

    private func buildRuntimeFromPersistedSelection(
        expected testCase: EffectiveASRMatrixCase
    ) -> BuiltEffectiveASRRuntime {
        let selectedEngine = ASREngine.selected(defaults: defaults)
        XCTAssertEqual(selectedEngine, testCase.engine, testCase.name)
        let route = ASRProviderRoute.dictation(
            selected: selectedEngine,
            isInstalled: { _ in true },
            cloudHasKey: { _ in true })
        let keyReader: ASRTranscriptionClientFactory.KeyReader = { [credentials] in
            credentials?.read($0)
        }
        let client = ASRTranscriptionClientFactory.batchClient(
            for: route,
            defaults: defaults,
            session: EffectiveASRStubURLProtocol.session(),
            keyReader: keyReader)
        if let volcengine = client as? VolcengineRealtimeTranscriptionAPI {
            return .volcengine(volcengine)
        }
        return .batch(client)
    }

    private func assertOnlyCredentialRead(for testCase: EffectiveASRMatrixCase) {
        XCTAssertEqual(
            credentials.recordedReads,
            [CapabilityCredentialAccount.apiKeyAccount(
                providerId: testCase.providerID,
                capability: .asr,
                plan: testCase.plan)],
            testCase.name)
    }

    @MainActor
    private func assertRuntime(
        _ runtime: BuiltEffectiveASRRuntime,
        matches testCase: EffectiveASRMatrixCase
    ) async throws {
        switch runtime {
        case .batch(let client):
            EffectiveASRStubURLProtocol.reset(responseData: responseData(for: testCase.runtime))
            let result = try await client.transcribe(
                audio: Data([0x01]),
                mimeType: "audio/wav",
                language: "zh")
            XCTAssertEqual(result.model, testCase.expectedModel, testCase.name)
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
        case .volcengine(let client):
            XCTAssertEqual(client.endpoint.host, "openspeech.bytedance.com", testCase.name)
            XCTAssertEqual(client.endpoint.path, "/api/v3/sauc/bigmodel_nostream", testCase.name)
            XCTAssertEqual(client.endpoint.apiKey, testCase.credential, testCase.name)
        }
    }

    private func responseData(for runtime: EffectiveASRMatrixCase.Runtime) -> Data {
        let json: String
        switch runtime {
        case .openAI, .custom:
            json = #"{"text":"ok"}"#
        case .mimo:
            json = #"{"choices":[{"message":{"content":"ok"}}]}"#
        case .gemini:
            json = #"{"candidates":[{"content":{"parts":[{"text":"ok"}]}}]}"#
        case .volcengine:
            json = "{}"
        }
        return json.data(using: .utf8)!
    }
}
