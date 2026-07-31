import Foundation

/// Perplexity Search API(`POST /search`)检索请求。
/// 文档:https://docs.perplexity.ai/api-reference/search-post
///
/// 走的是纯检索这一条,不是 sonar 作答模型的 `/chat/completions` —— 后者会自己给答案,
/// 与「App 检索、主模型作答」的路线冲突。
enum PerplexitySearchRequestBuilder {
    static let endpoint = "https://api.perplexity.ai/search"

    /// 文档:max_results 1~20,默认 10。
    static let maxResults = 20

    static func makeRequest(
        apiKey: String,
        query: String,
        maxResults count: Int,
        timeout: TimeInterval = 20
    ) throws -> URLRequest {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !trimmedQuery.isEmpty else { throw WebSearchError.notConfigured }
        guard let url = URL(string: endpoint) else {
            throw WebSearchError.badResponse("检索端点无效:\(endpoint)")
        }

        let body: [String: Any] = [
            "query": trimmedQuery,
            "max_results": min(max(count, 1), maxResults),
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = timeout
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}
