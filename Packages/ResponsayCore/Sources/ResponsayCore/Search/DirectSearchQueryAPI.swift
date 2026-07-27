import Foundation

/// 用主模型把长提问提炼成检索词(见 `SearchQueryDistiller`)。走和其他 App-direct 调用
/// 同一条 `/chat/completions` 路径,但强制关思考、给 20s 短超时——它是检索前的一步小事,
/// 不该拖慢整条联网作答。
public struct DirectSearchQueryAPI: Sendable {
    let endpoint: LLMEndpoint
    let client: LLMChatClient

    public init(endpoint: LLMEndpoint, session: URLSession = .shared) {
        // 思考关掉:提炼检索词不需要推理,开着只是慢。
        self.endpoint = LLMEndpoint(
            providerId: endpoint.providerId,
            baseURL: endpoint.baseURL,
            model: endpoint.model,
            apiKey: endpoint.apiKey,
            thinkingEnabled: false)
        self.client = LLMChatClient(session: session)
    }

    /// 未超限 → 原样返回(不调模型)。超限 → 让模型提炼;模型失败或输出不可用 → 截断兜底。
    /// 永不抛错:检索词提炼是锦上添花,不该让整条联网作答挂掉。
    public func searchQuery(for question: String, limit: Int) async -> String {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard SearchQueryDistiller.needsDistilling(trimmed, limit: limit) else { return trimmed }

        do {
            let request = try LLMChatRequestBuilder.makeRequest(
                endpoint: endpoint,
                system: SearchQueryDistiller.systemPrompt,
                user: SearchQueryDistiller.userPrompt(trimmed, limit: limit),
                timeout: 20)
            let raw = try await client.execute(request)
            if let distilled = SearchQueryDistiller.clean(raw, limit: limit) { return distilled }
        } catch {
            // 落到截断兜底。这里不记日志:提问原文属于用户内容,Diag 只收描述符。
        }
        return SearchQueryDistiller.truncated(trimmed, limit: limit)
    }
}
