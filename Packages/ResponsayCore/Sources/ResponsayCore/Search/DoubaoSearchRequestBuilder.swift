import Foundation

/// 火山引擎「豆包搜索 Global 版」检索请求。
/// 文档:https://docs.volcengine.com/docs/87772/2548026
///
/// 注意它**不是**方舟(Ark)的接口:域名、鉴权、请求体、响应体全都自成一套,
/// API Key 也另发一把(联网搜索控制台 → API Key 管理 → 按量后付费)。
/// 只支持后付费;每个火山账号每月 500 次免费额度;账号维度默认 5 QPS。
enum DoubaoSearchRequestBuilder {
    static let endpoint = "https://open.feedcoopapi.com/search_api/global_search"

    /// 文档:Query 1~100 字符(过长会截断),DocCount 最多 20 条。
    static let maxQueryLength = 100
    static let maxDocCount = 20

    /// 单个摘要片段的最大 tokens。文档上限 3000、推荐 1000 以内;
    /// 摘要要喂进模型的上下文,取 500(接口默认值)够用又不撑爆 prompt。
    static let snippetLength = 500

    static func makeRequest(
        apiKey: String,
        query: String,
        docCount: Int,
        timeout: TimeInterval = 20
    ) throws -> URLRequest {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !trimmedQuery.isEmpty else { throw WebSearchError.notConfigured }
        guard let url = URL(string: endpoint) else {
            throw WebSearchError.badResponse("检索端点无效:\(endpoint)")
        }

        // 接口自己也会截断，但截在我们这边才知道送出去的是什么。
        let body: [String: Any] = [
            "Query": String(trimmedQuery.prefix(maxQueryLength)),
            "DocCount": min(max(docCount, 1), maxDocCount),
            "MaxSnippetLength": snippetLength,
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
