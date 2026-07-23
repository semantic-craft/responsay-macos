import Testing
import Foundation
@testable import ResponsayCore

// Dedicated stub with its own static state so this suite never races the DirectStreamingChatClient suite.
final class TransportStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var body = ""
    nonisolated(unsafe) static var status = 200
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let resp = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil,
                                   headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body.data(using: .utf8)!)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

/// Exercises the shared `SSEStreamTransport` byte loop once, so the two request-builders
/// (`DirectStreamingChatClient`, `DirectArkResponsesStreamingClient`) don't each re-test it.
@Suite(.serialized)
struct SSEStreamTransportTests {
    private func session() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [TransportStubURLProtocol.self]
        return URLSession(configuration: cfg)
    }

    private static func stubRequest() -> URLRequest {
        var r = URLRequest(url: URL(string: "https://stub.local/v1/chat")!)
        r.httpMethod = "POST"
        return r
    }

    private func collect(_ stream: AsyncThrowingStream<TextStreamEvent, Error>) async throws -> [TextStreamEvent] {
        var events: [TextStreamEvent] = []
        for try await event in stream { events.append(event) }
        return events
    }

    @Test func streamsDeltasThenStopsOnTerminal() async throws {
        TransportStubURLProtocol.status = 200
        TransportStubURLProtocol.body = """
        data: {"choices":[{"delta":{"content":"Hel"}}]}
        data: {"choices":[{"delta":{"content":"lo"}}]}
        data: [DONE]
        data: {"choices":[{"delta":{"content":"AFTER"}}]}

        """
        let events = try await collect(
            SSEStreamTransport(session: session()).stream(parser: OpenAIStreamLineParser()) { Self.stubRequest() })
        #expect(events == [.delta("Hel"), .delta("lo"), .done])   // stops at .done; "AFTER" never read
    }

    @Test func nonSuccessStatusThrowsHTTPWithBody() async throws {
        TransportStubURLProtocol.status = 500
        TransportStubURLProtocol.body = "upstream boom"
        await #expect(throws: LLMError.self) {
            _ = try await collect(
                SSEStreamTransport(session: session()).stream(parser: OpenAIStreamLineParser()) { Self.stubRequest() })
        }
    }

    @Test func flushesTrailingLineWithoutNewline() async throws {
        TransportStubURLProtocol.status = 200
        TransportStubURLProtocol.body = #"data: {"choices":[{"delta":{"content":"tail"}}]}"#  // no trailing newline
        let events = try await collect(
            SSEStreamTransport(session: session()).stream(parser: OpenAIStreamLineParser()) { Self.stubRequest() })
        #expect(events == [.delta("tail")])
    }

    @Test func makeRequestThrowSurfacesAsTerminalError() async throws {
        TransportStubURLProtocol.status = 200
        TransportStubURLProtocol.body = "data: [DONE]\n"
        await #expect(throws: LLMError.self) {
            _ = try await collect(
                SSEStreamTransport(session: session()).stream(parser: OpenAIStreamLineParser()) {
                    throw LLMError.notConfigured
                })
        }
    }
}
