import Foundation

/// Streaming chat over a raw message array. `DirectStreamingChatClient` is the production
/// HTTP implementation; abstracting it lets the Voice Assistant be driven by a scripted
/// stream in tests, so the post-stream settling (returning to `.idle` so 重新生成 re-enables)
/// is verifiable without a network.
public protocol StreamingChatClient: Sendable {
    func stream(messages: [[String: String]]) -> AsyncThrowingStream<TextStreamEvent, Error>
}

/// A generic streaming chat client that accepts a raw array of messages.
/// Used by the Global Voice Assistant for multi-turn conversations. Only the request shape
/// (`/chat/completions` body + provider control merges) is provider-specific; the SSE byte loop,
/// HTTP gate, and cancellation live in `SSEStreamTransport`.
public final class DirectStreamingChatClient: StreamingChatClient {
    private let endpoint: LLMEndpoint
    private let searchEnabled: Bool
    private let session: URLSession
    private let parser = OpenAIStreamLineParser()

    public init(endpoint: LLMEndpoint, searchEnabled: Bool = false, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.searchEnabled = searchEnabled
        self.session = session
    }

    public func stream(messages: [[String: String]]) -> AsyncThrowingStream<TextStreamEvent, Error> {
        SSEStreamTransport(session: session).stream(parser: parser) { [endpoint, searchEnabled, messages] in
            guard endpoint.isConfigured else { throw LLMError.notConfigured }
            guard let url = LLMWire.chatCompletionsURL(base: endpoint.baseURL) else {
                throw LLMError.invalidEndpoint(endpoint.baseURL)
            }

            var body: [String: Any] = [
                "model": endpoint.model,
                "messages": messages,
                "stream": true,
            ]
            for (key, value) in LLMThinkingControl.extraBody(
                providerId: endpoint.providerId, model: endpoint.model,
                baseURLHost: endpoint.host, enabled: endpoint.thinkingEnabled, streaming: true) {
                body[key] = value
            }
            for (key, value) in LLMStreamOptionsControl.extraBody(
                providerId: endpoint.providerId, baseURLHost: endpoint.host) {
                body[key] = value
            }
            // Ask Anything is the only open-chat surface. Its web search is
            // opt-in, and fans out through each provider's official wire shape.
            for (key, value) in LLMSearchControl.extraBody(
                providerId: endpoint.providerId,
                baseURLHost: endpoint.host,
                searchEnabled: searchEnabled) {
                body[key] = value
            }

            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            for (key, value) in LLMWire.authHeaders(providerId: endpoint.providerId, key: endpoint.apiKey) {
                urlRequest.setValue(value, forHTTPHeaderField: key)
            }
            urlRequest.timeoutInterval = endpoint.isLocal ? 300 : 60
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
            return urlRequest
        }
    }
}
