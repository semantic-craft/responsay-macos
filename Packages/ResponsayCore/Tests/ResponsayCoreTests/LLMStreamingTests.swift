import Testing
import Foundation
@testable import ResponsayCore

// Dedicated stub for streaming (own static state).
final class LLMStreamStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var body = ""
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var requestBody = Data()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requestBody = request.httpBody ?? Self.readBodyStream(request.httpBodyStream)
        let resp = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil,
                                   headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body.data(using: .utf8)!)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    private static func readBodyStream(_ stream: InputStream?) -> Data {
        guard let stream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private func streamStubSession() -> URLSession {
    let cfg = URLSessionConfiguration.ephemeral
    cfg.protocolClasses = [LLMStreamStubURLProtocol.self]
    return URLSession(configuration: cfg)
}

struct OpenAIStreamLineParserTests {
    private let p = OpenAIStreamLineParser()
    @Test func parsesVendorDeltaDoneErrorAndIgnores() {
        #expect(p.event(for: #"data: {"choices":[{"delta":{"content":"Hi"}}]}"#) == .delta("Hi"))
        #expect(p.event(for: "data: [DONE]") == .done)
        #expect(p.event(for: #"data: {"error":{"message":"bad"}}"#) == .failed("bad"))
        #expect(p.event(for: #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#) == nil)
        #expect(p.event(for: "") == nil)
        #expect(p.event(for: ": keep-alive") == nil)
    }

    @Test func errorAsPlainString_andCRLFTrimmed() {
        #expect(p.event(for: #"data: {"error":"rate limited"}"#) == .failed("rate limited"))  // string error keeps message
        #expect(p.event(for: "data: [DONE]\r") == .done)   // trailing CR (CRLF framing) trimmed
    }

    @Test func qwenThinkingChunksIgnoreReasoningAndUsage() {
        #expect(p.event(for: #"data: {"choices":[{"delta":{"content":null,"role":"assistant","reasoning_content":"分析中"},"finish_reason":null}]}"#) == nil)
        #expect(p.event(for: #"data: {"choices":[{"delta":{"content":"答案","reasoning_content":""},"finish_reason":null}]}"#) == .delta("答案"))
        #expect(p.event(for: #"data: {"choices":[],"usage":{"prompt_tokens":10,"completion_tokens":2,"total_tokens":12}}"#) == nil)
        #expect(p.event(for: "data: [DONE]") == .done)
    }

    @Test func mimoUsageReasoningTokensAreIgnored() {
        #expect(p.event(for: #"data: {"choices":[],"usage":{"prompt_tokens":10,"completion_tokens":2,"total_tokens":12,"completion_tokens_details":{"reasoning_tokens":3}}}"#) == nil)
    }
}

struct LLMStreamOptionsControlTests {
    @Test func qwenAndDoubaoAddUsageStreamOptions() {
        let qwen = LLMStreamOptionsControl.extraBody(providerId: "qwen", baseURLHost: "dashscope.aliyuncs.com")
        let qwenStreamOptions = qwen["stream_options"] as? [String: Bool]
        #expect(qwenStreamOptions?["include_usage"] == true)

        let doubao = LLMStreamOptionsControl.extraBody(providerId: "doubao", baseURLHost: "ark.cn-beijing.volces.com")
        let doubaoStreamOptions = doubao["stream_options"] as? [String: Bool]
        #expect(doubaoStreamOptions?["include_usage"] == true)

        #expect(LLMStreamOptionsControl.extraBody(providerId: "openai", baseURLHost: "api.openai.com").isEmpty)
    }
}

@Suite(.serialized)
struct DirectStreamingChatClientStreamingTests {
    private func endpoint() -> LLMEndpoint {
        LLMEndpoint(providerId: "openai", baseURL: "https://api.openai.com/v1", model: "gpt-4.1", apiKey: "sk-1")
    }

    private func qwenEndpoint(thinking: Bool = false) -> LLMEndpoint {
        LLMEndpoint(providerId: "qwen", baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
                    model: "qwen-flash", apiKey: "sk-1", thinkingEnabled: thinking)
    }

    private func collect(_ stream: AsyncThrowingStream<TextStreamEvent, Error>) async throws -> [TextStreamEvent] {
        var events: [TextStreamEvent] = []
        for try await event in stream { events.append(event) }
        return events
    }

    @Test func voiceAssistantSearchEnabledAddsProviderSearchBody() async throws {
        LLMStreamStubURLProtocol.status = 200
        LLMStreamStubURLProtocol.requestBody = Data()
        LLMStreamStubURLProtocol.body = "data: [DONE]\n\n"
        let client = DirectStreamingChatClient(
            endpoint: qwenEndpoint(),
            searchEnabled: true,
            session: streamStubSession())

        _ = try await collect(client.stream(messages: [
            ["role": "system", "content": "You are concise."],
            ["role": "user", "content": "今天发生了什么？"],
        ]))

        let body = try #require(JSONSerialization.jsonObject(with: LLMStreamStubURLProtocol.requestBody) as? [String: Any])
        #expect(body["stream"] as? Bool == true)
        #expect(body["enable_search"] as? Bool == true)
        #expect(body["enable_thinking"] as? Bool == false)
        let streamOptions = try #require(body["stream_options"] as? [String: Any])
        #expect(streamOptions["include_usage"] as? Bool == true)
    }

    @Test func voiceAssistantSearchFlagIsNoopForUnsupportedProvider() async throws {
        LLMStreamStubURLProtocol.status = 200
        LLMStreamStubURLProtocol.requestBody = Data()
        LLMStreamStubURLProtocol.body = "data: [DONE]\n\n"
        let client = DirectStreamingChatClient(
            endpoint: endpoint(),
            searchEnabled: true,
            session: streamStubSession())

        _ = try await collect(client.stream(messages: [
            ["role": "user", "content": "What happened today?"],
        ]))

        let body = try #require(JSONSerialization.jsonObject(with: LLMStreamStubURLProtocol.requestBody) as? [String: Any])
        #expect(body["enable_search"] == nil)
        #expect(body["tools"] == nil)
    }
}
