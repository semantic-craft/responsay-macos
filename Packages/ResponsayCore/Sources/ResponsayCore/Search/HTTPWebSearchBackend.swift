import Foundation

/// `WebSearchBackend` 的生产实现:一个 URLSession + 按 `kind` 分派的请求/解析对。
/// session 可注入,所以整条路径能用 stub URLProtocol 无网络测(同 `LLMChatClient` 的做法)。
public struct HTTPWebSearchBackend: WebSearchBackend {
    public let kind: WebSearchBackendKind
    private let apiKey: String
    private let session: URLSession

    public init(kind: WebSearchBackendKind, apiKey: String, session: URLSession = .shared) {
        self.kind = kind
        self.apiKey = apiKey
        self.session = session
    }

    public func search(query: String, limit: Int) async throws -> [WebSearchDocument] {
        let request: URLRequest
        switch kind {
        case .doubao:
            request = try DoubaoSearchRequestBuilder.makeRequest(
                apiKey: apiKey, query: query, docCount: limit)
        case .perplexity:
            request = try PerplexitySearchRequestBuilder.makeRequest(
                apiKey: apiKey, query: query, maxResults: limit)
        }

        let data = try await execute(request)
        switch kind {
        case .doubao:     return try DoubaoSearchResultParser.parse(data)
        case .perplexity: return try PerplexitySearchResultParser.parse(data)
        }
    }

    /// 豆包搜索把鉴权/额度错误放在 200 的响应体里(`ResponseMetadata.Error`),
    /// Perplexity 用 HTTP 状态码 —— 所以非 2xx 在这里拦,业务错误码留给各自的 parser。
    private func execute(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw WebSearchError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw WebSearchError.network("无 HTTP 响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw WebSearchError.http(
                status: http.statusCode,
                body: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }
}
