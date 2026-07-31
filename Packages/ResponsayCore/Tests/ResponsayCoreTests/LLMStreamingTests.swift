import Testing
import Foundation
@testable import ResponsayCore

// Dedicated stub for streaming (own static state).
final class LLMStreamStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var body = ""
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var requestBody = Data()
    nonisolated(unsafe) static var requestURL: URL?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requestURL = request.url
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

    @Test func legacyChatThinkingChunksIgnoreReasoningAndUsage() {
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
    @Test func qwenResponsesOmitsChatStreamOptionsWhileDoubaoChatKeepsThem() {
        let qwen = LLMStreamOptionsControl.extraBody(providerId: "qwen", baseURLHost: "dashscope.aliyuncs.com")
        #expect(qwen.isEmpty)

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
        LLMStreamStubURLProtocol.body = """
        data: {"type":"response.output_text.delta","delta":"今天晴"}

        data: {"type":"response.completed","response":{"status":"completed"}}

        """
        let client = DirectStreamingChatClient(
            endpoint: qwenEndpoint(),
            searchEnabled: true,
            session: streamStubSession())

        let events = try await collect(client.stream(messages: [
            ["role": "system", "content": "You are concise."],
            ["role": "user", "content": "今天发生了什么？"],
        ]))
        #expect(events == [.delta("今天晴"), .done])

        let body = try #require(JSONSerialization.jsonObject(with: LLMStreamStubURLProtocol.requestBody) as? [String: Any])
        #expect(LLMStreamStubURLProtocol.requestURL?.path == "/compatible-mode/v1/responses")
        #expect(body["stream"] as? Bool == true)
        #expect(body["store"] as? Bool == false)
        #expect(body["input"] != nil)
        #expect(body["messages"] == nil)
        let tools = try #require(body["tools"] as? [[String: Any]])
        #expect(tools.count == 1)
        #expect(tools.first?["type"] as? String == "web_search")
        #expect(body["tool_choice"] as? String == "auto")   // required breaks the Responses server tool loop (live eval 2026-07-31)
        #expect((body["reasoning"] as? [String: String])?["effort"] == "none")
        #expect(body["enable_search"] == nil)
        #expect(body["enable_thinking"] == nil)
        #expect(body["stream_options"] == nil)
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
