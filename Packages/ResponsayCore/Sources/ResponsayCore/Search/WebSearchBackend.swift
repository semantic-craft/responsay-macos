import Foundation

// MARK: - WebSearchBackend
//
// 独立检索后端 — 与 LLM provider 解耦的第三条联网路线。
//
// 前两条是「模型自带联网」:`LLMSearchControl`(Qwen/智谱/MiMo 走 /chat/completions 的
// 联网参数)与 `ArkResponsesSearchRequestBuilder`(豆包方舟/OpenAI 走 /responses 的
// web_search 工具)。它们都是模型自己搜、自己答,搜索质量与来源格式由模型决定。
//
// 这一条是 App 先检索、再把结果喂给用户当前配的主模型作答(见 `WebSearchContextBuilder`)。
// 好处:主模型不必支持联网;来源是检索服务返回的结构化字段(标题/站点/发布时间),
// 不用再从模型回答里抠 URL。代价:两段式,比模型自带联网多一次往返。

/// 支持的检索服务。每家一把独立 API Key(与 LLM 的 BYOK 密钥无关)。
public enum WebSearchBackendKind: String, Sendable, CaseIterable {
    /// 火山引擎 豆包搜索 Global 版(原「联网搜索 / 融合信息搜索」)。
    /// Key 由 联网搜索控制台 签发,**不是**方舟的 LLM API Key。
    case doubao = "doubao-search"
    /// Perplexity Search API(`/search`)。纯检索,与 sonar 作答模型是两条不同的路。
    case perplexity = "perplexity"

    public var displayName: String {
        switch self {
        case .doubao:     return "豆包搜索"
        case .perplexity: return "Perplexity"
        }
    }

    /// 胶囊署名的单字纹章,与 `VoiceAssistantSearchModelSettings.capsuleSource` 同构。
    public var monogram: String {
        switch self {
        case .doubao:     return "豆"
        case .perplexity: return "P"
        }
    }

    /// 检索词长度上限。豆包搜索 Global 版是**硬限制**(文档:Query 1~100 字符,过长会截断);
    /// Perplexity 未公开上限,沿用同一阈值——语音提问动辄几百字,两家都该先提炼再搜,
    /// 一个阈值让两条路行为一致(见 `SearchQueryDistiller`)。
    public var queryCharacterLimit: Int { 100 }
}

/// 一条检索结果。字段取各家的交集 + 我们真正会展示的部分。
public struct WebSearchDocument: Sendable, Equatable {
    public let title: String
    public let url: String
    public let snippet: String
    /// 站点名(豆包搜索给「抖音百科」这类中文站名;Perplexity 不给,留空)。
    public let hostname: String
    /// 网页发布时间,原样透传(各家格式不一,不做归一化)。搜不到就是空串。
    public let publishTime: String

    public init(
        title: String,
        url: String,
        snippet: String,
        hostname: String = "",
        publishTime: String = ""
    ) {
        self.title = title
        self.url = url
        self.snippet = snippet
        self.hostname = hostname
        self.publishTime = publishTime
    }
}

/// 检索失败的原因。`provider` 携带服务商自己的错误码 —— 用户刚贴完 Key 时,
/// 「700901 APIKey 无效」比「HTTP 200 但没结果」有用得多。
public enum WebSearchError: LocalizedError, Equatable {
    case notConfigured
    case network(String)
    case http(status: Int, body: String)
    case provider(code: String, message: String)
    case badResponse(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "还没填搜索服务的 API Key。请在 设置 →「改写设置」→ 任意提问 里填好。"
        case .network(let message):
            return "搜索网络错误:\(message)"
        case .http(let status, let body):
            let snippet = body.prefix(200)
            return "搜索服务返回 HTTP \(status)。\(snippet.isEmpty ? "请检查 API Key 与服务开通状态。" : String(snippet))"
        case .provider(let code, let message):
            return "搜索服务报错 \(code):\(message)"
        case .badResponse(let message):
            return "无法解析搜索结果:\(message)"
        }
    }
}

/// 检索后端。实现只负责「拿到结果」,不作答、不改写。
public protocol WebSearchBackend: Sendable {
    var kind: WebSearchBackendKind { get }
    /// - Parameter limit: 期望的结果条数;各家自己夹到合法区间。
    func search(query: String, limit: Int) async throws -> [WebSearchDocument]
}
