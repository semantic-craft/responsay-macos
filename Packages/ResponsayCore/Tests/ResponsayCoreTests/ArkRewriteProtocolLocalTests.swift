import Foundation
import Testing
@testable import ResponsayCore

/// 本地（无网络）验证 eval 传输层的 body 语义：URLProtocol 里 httpBody/httpBodyStream 的
/// 真实形态、drain 是否可靠、chat→ark /responses 改写是否产出完整 body。
/// 回环协议：拦截后不联网，直接回一个合成 Responses 应答，并把收到的 body 长度塞进应答里。
final class LoopbackProbeProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var lastSeenBodyBytes = -1
    nonisolated(unsafe) static var lastHadStream = false
    nonisolated(unsafe) static var lastHadHTTPBody = false
    nonisolated(unsafe) static var lastRewrittenBodyBytes = -1
    nonisolated(unsafe) static var lastRewrittenPath = ""

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastHadStream = request.httpBodyStream != nil
        Self.lastHadHTTPBody = request.httpBody != nil

        // 复用真实改写逻辑（doubao 开关由 caller 设定）。顺序关键：改写在先——
        // passthrough 分支绝不能消费流（流是一次性的，读过转发即空 body 400）。
        let rewritten = ArkRewriteURLProtocol.rewrittenRequest(request)
        Self.lastRewrittenPath = rewritten.url?.path ?? ""
        Self.lastRewrittenBodyBytes = rewritten.httpBody?.count
            ?? (rewritten.httpBodyStream != nil ? -2 : -1)   // -2 = 还是 live stream

        // 改写之后再读，证明 passthrough 分支留下的流仍然可读（未被消费）。
        let body = ArkRewriteURLProtocol.bodyData(of: request)
        Self.lastSeenBodyBytes = body?.count ?? -1

        let payload: [String: Any] = [
            "object": "response", "status": "completed", "model": "loopback",
            "output": [["type": "message", "content": [["type": "output_text", "text": "OK"]]]],
        ]
        let data = try! JSONSerialization.data(withJSONObject: payload)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct ArkRewriteProtocolLocalTests {
    private func loopbackSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LoopbackProbeProtocol.self]
        return URLSession(configuration: config)
    }

    @Test func qwenRequestBodySurvivesProtocolLayer() async throws {
        ArkRewriteURLProtocol.rewriteChatToArkResponses = false
        let endpoint = LLMEndpoint(
            providerId: "qwen", baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
            model: "qwen3.7-max", apiKey: "sk-test", thinkingEnabled: false)
        let request = try LLMChatRequestBuilder.makeRequest(endpoint: endpoint, system: "S", user: "U")
        let reply = try await LLMChatClient(session: loopbackSession()).execute(request)
        #expect(reply == "OK")
        print("qwen: hadHTTPBody=\(LoopbackProbeProtocol.lastHadHTTPBody) hadStream=\(LoopbackProbeProtocol.lastHadStream) seen=\(LoopbackProbeProtocol.lastSeenBodyBytes) rewrittenBytes=\(LoopbackProbeProtocol.lastRewrittenBodyBytes) path=\(LoopbackProbeProtocol.lastRewrittenPath)")
        // passthrough：请求原样、流未被消费（改写后仍能读出完整 body 字节）。
        #expect(LoopbackProbeProtocol.lastRewrittenBodyBytes == -2, "passthrough 必须保留 live stream")
        #expect(LoopbackProbeProtocol.lastSeenBodyBytes > 0, "流在改写后必须仍可读（未被消费）")
    }

    @Test func doubaoChatRewritesToArkResponsesWithFullBody() async throws {
        ArkRewriteURLProtocol.rewriteChatToArkResponses = true
        defer { ArkRewriteURLProtocol.rewriteChatToArkResponses = false }
        let endpoint = LLMEndpoint(
            providerId: "doubao", baseURL: "https://ark.cn-beijing.volces.com/api/v3",
            model: "doubao-seed-2-1-pro-260628", apiKey: "ark-test", thinkingEnabled: false)
        let request = try LLMChatRequestBuilder.makeRequest(endpoint: endpoint, system: "S", user: "U")
        let reply = try await LLMChatClient(session: loopbackSession()).execute(request)
        #expect(reply == "OK")
        print("doubao: hadHTTPBody=\(LoopbackProbeProtocol.lastHadHTTPBody) hadStream=\(LoopbackProbeProtocol.lastHadStream) seen=\(LoopbackProbeProtocol.lastSeenBodyBytes) rewrittenBytes=\(LoopbackProbeProtocol.lastRewrittenBodyBytes) path=\(LoopbackProbeProtocol.lastRewrittenPath)")
        #expect(LoopbackProbeProtocol.lastRewrittenPath.hasSuffix("/responses"))
        #expect(LoopbackProbeProtocol.lastRewrittenBodyBytes > 0)
    }
}
