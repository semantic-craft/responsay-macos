import Foundation

/// Streaming chat over Volcengine Ark's **Responses API** (`/responses`), the only route that
/// exposes Doubao's built-in `web_search` plugin. Conforms to `StreamingChatClient` so the Voice
/// Assistant (任意提问) can drive it exactly like the `/chat/completions` client — the dispatch in
/// `CaptureController+AskAnything` picks this one when the resolved 联网 provider is 豆包/方舟.
///
/// Only the request differs from `DirectStreamingChatClient`: the body is the Responses shape
/// (`input` items + `tools:[{web_search}]`) and frames decode via `ArkResponsesStreamLineParser`.
/// The shared SSE byte loop, HTTP gate, and cancellation live in `SSEStreamTransport`.
public final class DirectArkResponsesStreamingClient: StreamingChatClient {
    private let endpoint: LLMEndpoint
    private let searchEnabled: Bool
    private let session: URLSession
    private let parser = ArkResponsesStreamLineParser()

    public init(endpoint: LLMEndpoint, searchEnabled: Bool = true, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.searchEnabled = searchEnabled
        self.session = session
    }

    public func stream(messages: [[String: String]]) -> AsyncThrowingStream<TextStreamEvent, Error> {
        SSEStreamTransport(session: session).stream(parser: parser) { [endpoint, searchEnabled, messages] in
            guard endpoint.isConfigured else { throw LLMError.notConfigured }
            guard let url = ArkResponsesSearchRequestBuilder.responsesURL(base: endpoint.baseURL) else {
                throw LLMError.invalidEndpoint(endpoint.baseURL)
            }

            let body = ArkResponsesSearchRequestBuilder.responsesBody(
                model: endpoint.model,
                input: messages.map(Self.inputItem),
                stream: true,
                thinkingEnabled: endpoint.thinkingEnabled,
                searchEnabled: searchEnabled,
                isOpenAI: ArkResponsesSearchRequestBuilder.isOpenAI(
                    providerId: endpoint.providerId, baseURLHost: endpoint.host))

            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            for (key, value) in LLMWire.authHeaders(providerId: endpoint.providerId, key: endpoint.apiKey) {
                urlRequest.setValue(value, forHTTPHeaderField: key)
            }
            urlRequest.timeoutInterval = 90
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
            return urlRequest
        }
    }

    /// Map a chat `{role, content}` pair to a Responses `input` item. Every role — assistant
    /// history included — goes as an `input_text` EasyInputMessage; the Responses API presumes an
    /// `assistant`-role input message is a prior model turn. Tagging it `output_text` instead made
    /// Ark parse it as a full *output* message, which then requires `id`+`status`+`type` we don't
    /// carry → HTTP 400 `MissingParameter: input.status` on the 2nd turn (追问, the first with
    /// assistant history). See OpenAI Responses `EasyInputMessage` vs `ResponseOutputMessage`.
    static func inputItem(_ message: [String: String]) -> [String: Any] {
        [
            "role": message["role"] ?? "user",
            "content": [["type": "input_text", "text": message["content"] ?? ""]],
        ]
    }
}
