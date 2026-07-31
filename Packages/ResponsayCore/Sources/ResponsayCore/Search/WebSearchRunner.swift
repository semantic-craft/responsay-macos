import Foundation

/// 「检索 → 拼上下文」这一段的编排:提炼检索词 → 调后端 → 拼成喂给模型的围栏块。
/// 抽在 core 里,是为了让这段逻辑离开 `@MainActor` 的 CaptureController、能单测。
public struct WebSearchRunner: Sendable {
    /// 默认取几条。豆包搜索默认 10 条、上限 20,但每条摘要 500 tokens——10 条就是
    /// 五千 tokens 的上下文,对一句语音问答太重。5 条够覆盖,也不撑爆 prompt。
    public static let defaultResultCount = 5

    public let backend: any WebSearchBackend
    /// 检索词提炼用的主模型。nil = 没有可用模型,超长提问退回截断。
    private let queryAPI: DirectSearchQueryAPI?

    public init(backend: any WebSearchBackend, queryAPI: DirectSearchQueryAPI? = nil) {
        self.backend = backend
        self.queryAPI = queryAPI
    }

    /// 供模型作答的检索上下文块。nil = 搜到 0 条(不是错误:搜不到 ≠ 不存在,
    /// 调用方据此退回不带检索的普通作答)。检索本身失败会抛 `WebSearchError`。
    public func context(
        for question: String,
        limit: Int = WebSearchRunner.defaultResultCount
    ) async throws -> String? {
        let documents = try await documents(for: question, limit: limit)
        return WebSearchContextBuilder.context(documents: documents)
    }

    /// 原始结果。法律核验要的是结构化来源(标题/URL/摘要),不是喂给模型的文本块。
    public func documents(
        for question: String,
        limit: Int = WebSearchRunner.defaultResultCount
    ) async throws -> [WebSearchDocument] {
        try await backend.search(query: await searchQuery(for: question), limit: limit)
    }

    /// 超过后端上限才让模型提炼;没有可用模型就截断。
    func searchQuery(for question: String) async -> String {
        let limit = backend.kind.queryCharacterLimit
        guard let queryAPI else { return SearchQueryDistiller.truncated(question, limit: limit) }
        return await queryAPI.searchQuery(for: question, limit: limit)
    }
}
