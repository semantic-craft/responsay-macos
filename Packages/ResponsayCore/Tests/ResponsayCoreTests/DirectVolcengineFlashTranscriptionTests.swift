import Foundation
import Testing
@testable import ResponsayCore

/// Volcengine 大模型录音文件识别 标准版 2.0 (`volc.seedasr.auc`) is an async two-stage API:
/// POST `/auc/bigmodel/submit` (clip inline as base64), then poll `/auc/bigmodel/query` with the
/// same `X-Api-Request-Id` until `X-Api-Status-Code` is done. New-console `X-Api-Key` auth.
/// These tests pin that flow for the BYOK app-direct client.
private final class VolcStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var submitStatus = "20000000"
    /// Sequenced query responses: (X-Api-Status-Code, body). Consumed one per query call;
    /// the last entry repeats if polled further.
    nonisolated(unsafe) static var queryResponses: [(String, Data)] = []
    nonisolated(unsafe) static var queryIndex = 0
    nonisolated(unsafe) static var submitURL: URL?
    nonisolated(unsafe) static var queryURL: URL?
    nonisolated(unsafe) static var submitHeaders: [String: String] = [:]
    nonisolated(unsafe) static var submitBody = Data()
    nonisolated(unsafe) static var queryCount = 0

    static func reset() {
        submitStatus = "20000000"; queryResponses = []; queryIndex = 0
        submitURL = nil; queryURL = nil; submitHeaders = [:]; submitBody = Data(); queryCount = 0
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        let isSubmit = path.hasSuffix("/submit")
        let code: String
        let body: Data
        if isSubmit {
            Self.submitURL = request.url
            Self.submitHeaders = request.allHTTPHeaderFields ?? [:]
            Self.submitBody = request.httpBody ?? Self.readBody(request.httpBodyStream)
            code = Self.submitStatus
            body = Data("{}".utf8)
        } else {
            Self.queryURL = request.url
            Self.queryCount += 1
            if Self.queryResponses.isEmpty {
                code = "20000000"; body = Data("{}".utf8)
            } else {
                let i = min(Self.queryIndex, Self.queryResponses.count - 1)
                (code, body) = Self.queryResponses[i]
                Self.queryIndex += 1
            }
        }
        let resp = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil,
            headerFields: ["X-Api-Status-Code": code, "X-Api-Message": "OK"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    private static func readBody(_ stream: InputStream?) -> Data {
        guard let stream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}

private func volcStubbedSession() -> URLSession {
    let cfg = URLSessionConfiguration.ephemeral
    cfg.protocolClasses = [VolcStubURLProtocol.self]
    return URLSession(configuration: cfg)
}

private func makeAPI(session: URLSession) -> DirectVolcengineFlashTranscriptionAPI {
    DirectVolcengineFlashTranscriptionAPI(
        session: session,
        modelProvider: { "bigmodel" },
        apiKeyProvider: { "volc-key" },
        requestIDProvider: { "task-1" },
        pollInterval: 0,
        maxPolls: 5)
}

@Suite(.serialized)
struct DirectVolcengineFlashTranscriptionTests {

    @Test func submitThenQueryPostsStandard2RequestAndReturnsText() async throws {
        VolcStubURLProtocol.reset()
        VolcStubURLProtocol.queryResponses = [
            ("20000000", """
            {"result":{"text":"关闭透传。"}}
            """.data(using: .utf8)!),
        ]
        let result = try await makeAPI(session: volcStubbedSession())
            .transcribe(audio: Data([0x01, 0x02]), mimeType: "audio/wav", language: "zh-CN")

        // submit: path + new-console headers + inline base64 body
        #expect(VolcStubURLProtocol.submitURL?.path == "/api/v3/auc/bigmodel/submit")
        #expect(VolcStubURLProtocol.submitHeaders["X-Api-Key"] == "volc-key")
        #expect(VolcStubURLProtocol.submitHeaders["X-Api-Resource-Id"] == "volc.seedasr.auc")
        #expect(VolcStubURLProtocol.submitHeaders["X-Api-Request-Id"] == "task-1")
        #expect(VolcStubURLProtocol.submitHeaders["X-Api-Sequence"] == "-1")
        let body = try #require(JSONSerialization.jsonObject(with: VolcStubURLProtocol.submitBody) as? [String: Any])
        let audio = try #require(body["audio"] as? [String: Any])
        #expect(audio["data"] as? String == Data([0x01, 0x02]).base64EncodedString())
        #expect(audio["format"] as? String == "wav")
        #expect(audio["url"] == nil)
        let request = try #require(body["request"] as? [String: Any])
        #expect(request["model_name"] as? String == "bigmodel")

        // query: same task id, dedicated endpoint
        #expect(VolcStubURLProtocol.queryURL?.path == "/api/v3/auc/bigmodel/query")
        #expect(result.text == "关闭透传。")
        #expect(result.provider == "volcengine-flash")
        #expect(result.model == "bigmodel")
        #expect(result.language == "auto")
    }

    @Test func pollsWhileProcessingThenReturnsDone() async throws {
        VolcStubURLProtocol.reset()
        VolcStubURLProtocol.queryResponses = [
            ("20000002", Data("{}".utf8)),   // queued
            ("20000001", Data("{}".utf8)),   // processing
            ("20000000", """
            {"result":{"text":"处理完成。"}}
            """.data(using: .utf8)!),
        ]
        let result = try await makeAPI(session: volcStubbedSession())
            .transcribe(audio: Data([0x03]), mimeType: "audio/wav", language: "zh")
        #expect(result.text == "处理完成。")
        #expect(VolcStubURLProtocol.queryCount == 3)
    }

    @Test func silentAudioThrows() async throws {
        VolcStubURLProtocol.reset()
        VolcStubURLProtocol.queryResponses = [("20000003", Data("{}".utf8))]
        await #expect(throws: (any Error).self) {
            _ = try await makeAPI(session: volcStubbedSession())
                .transcribe(audio: Data([0x01]), mimeType: "audio/wav", language: "zh")
        }
    }

    @Test func submitFailureThrowsBeforePolling() async throws {
        VolcStubURLProtocol.reset()
        VolcStubURLProtocol.submitStatus = "45000001"
        await #expect(throws: (any Error).self) {
            _ = try await makeAPI(session: volcStubbedSession())
                .transcribe(audio: Data([0x01]), mimeType: "audio/wav", language: "zh")
        }
        #expect(VolcStubURLProtocol.queryCount == 0)
    }

    @Test func missingKeyThrowsBeforeNetwork() async throws {
        VolcStubURLProtocol.reset()
        let api = DirectVolcengineFlashTranscriptionAPI(
            session: volcStubbedSession(), apiKeyProvider: { "  " }, pollInterval: 0)
        await #expect(throws: (any Error).self) {
            _ = try await api.transcribe(audio: Data([0x01]), mimeType: "audio/wav", language: "zh")
        }
    }
}
