import Foundation

// MARK: - 得理(Delilegal)检索 client
//
// 法律 AI 提供商之一（与元典并列，可选 BYOK）。检索类技能「接了更好」的数据后端：
// 没配 key → 技能走云端 LLM + 浏览器深链；配了 key → 走本 client 拿权威案例/法规。
// ⚠️ 端点两代并存（见 generation），请求体不同；真实 key 到手须 live 定版（T3）。
// API key 由调用方（macOS 层从 Keychain `byok.delilegal`）传入；本类型不持久化 key。

public enum DelilegalEndpointGeneration: String, Sendable, CaseIterable {
    case skill      // /api/v1/skill/*    + condition 嵌套（v1.0.9，新版，默认）
    case generice   // /api/v1/generice/* + 扁平 query（v1.0.0；"generice" 是得理真实拼写）
}

public enum DelilegalResource: String, Sendable {
    case caseList = "case"
    case lawList = "law"
}

public struct DelilegalRequestContext: Sendable {
    public let sessionId: String      // 每安装持久化 UUID
    public let skillId: String        // 取自 SKILL.md frontmatter name
    public let skillVersion: String
    public init(sessionId: String, skillId: String, skillVersion: String) {
        self.sessionId = sessionId
        self.skillId = skillId
        self.skillVersion = skillVersion
    }
}

public struct DelilegalClient: Sendable {
    public let apiKey: String
    public let generation: DelilegalEndpointGeneration
    private static let base = "https://platform.delilegal.com/api/v1"

    public init(apiKey: String, generation: DelilegalEndpointGeneration = .skill) {
        self.apiKey = apiKey
        self.generation = generation
    }

    public func endpointURL(_ resource: DelilegalResource) -> URL {
        URL(string: "\(Self.base)/\(generation.rawValue)/\(resource.rawValue)/list")!
    }

    /// 构造检索请求。keywords/longText 二选一；semantic 仅新版法规语义检索用。
    public func buildRequest(resource: DelilegalResource, context: DelilegalRequestContext,
                             keywords: [String]? = nil, longText: String? = nil, semantic: Bool = false,
                             page: Int = 1, size: Int = 5,
                             sortField: String = "correlation", sortOrder: String = "desc") -> URLRequest {
        var req = URLRequest(url: endpointURL(resource))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue(context.sessionId, forHTTPHeaderField: "Session-Id")
        req.setValue(context.skillId, forHTTPHeaderField: "Skill-Id")
        req.setValue(context.skillVersion, forHTTPHeaderField: "Skill-Version")

        var body: [String: Any] = [
            "pageNo": page, "pageSize": size, "sortField": sortField, "sortOrder": sortOrder,
        ]
        switch generation {
        case .skill:
            var cond: [String: Any] = [:]
            if let lt = longText {
                cond["longText"] = lt
            } else if let kw = keywords {
                cond["keywords"] = kw
                if semantic { cond["fieldName"] = "semantic" }
            }
            body["condition"] = cond
        case .generice:
            if let lt = longText {
                body["longText"] = lt
            } else if let kw = keywords {
                body["query"] = kw.joined(separator: " ")
            }
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        return req
    }

    public static func decode(_ data: Data) throws -> DelilegalSearchResponse {
        try JSONDecoder().decode(DelilegalSearchResponse.self, from: data)
    }

    /// 发起检索（live 网络，T3/HITL）。组合已测的 `buildRequest` + `decode`。
    public func search(resource: DelilegalResource, context: DelilegalRequestContext,
                       keywords: [String]? = nil, longText: String? = nil, semantic: Bool = false,
                       page: Int = 1, size: Int = 5,
                       sortField: String = "correlation", sortOrder: String = "desc",
                       session: URLSession = .shared) async throws -> DelilegalSearchResponse {
        let req = buildRequest(resource: resource, context: context, keywords: keywords, longText: longText,
                               semantic: semantic, page: page, size: size,
                               sortField: sortField, sortOrder: sortOrder)
        let (data, _) = try await session.data(for: req)
        return try Self.decode(data)
    }
}

// MARK: - 响应（Decodable，宽容解码；得理线上字段名历史上不稳定 → 别名兜底）

public struct DelilegalSearchResponse: Decodable, Sendable {
    public let success: Bool?
    public let code: Int?
    public let msg: String?
    public let body: Body?

    public struct Body: Decodable, Sendable {
        public let data: [Item]
        public let totalCount: Int?
        public let totalPage: Int?
        public let queryId: String?

        enum K: String, CodingKey { case data, list, records, totalCount, total, totalPage, queryId }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: K.self)
            data = (try? c.decode([Item].self, forKey: .data))
                ?? (try? c.decode([Item].self, forKey: .list))
                ?? (try? c.decode([Item].self, forKey: .records)) ?? []
            totalCount = (try? c.decode(Int.self, forKey: .totalCount)) ?? (try? c.decode(Int.self, forKey: .total))
            totalPage = try? c.decode(Int.self, forKey: .totalPage)
            queryId = try? c.decode(String.self, forKey: .queryId)
        }
    }

    public struct Item: Decodable, Sendable {
        // 案例字段
        public let title: String?
        public let caseNumber: String?
        public let cause: String?
        public let court: String?
        public let levelOfTrial: String?
        public let judgementType: String?
        public let judgementDate: String?
        public let publishTypeName: String?
        public let content: String?
        public let highlights: String?
        // 法规字段
        public let timelinessName: String?
        public let levelName: String?
        public let publisherName: String?
        public let issuedNo: String?
        public let publishDate: String?
        public let activeDate: String?

        enum K: String, CodingKey {
            case title, name, caseNumber, caseNo, cause, causeName, court, courtName
            case levelOfTrial, courtLevelName, judgementType, judgementTypeName
            case judgementDate, judgeDate, publishTypeName, publishType, content, highlights
            case timelinessName, levelName, publisherName, issuedNo, publishDate, activeDate
        }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: K.self)
            func s(_ keys: K...) -> String? {
                for k in keys { if let v = try? c.decode(String.self, forKey: k) { return v } }
                return nil
            }
            title = s(.title, .name, .caseNumber)
            caseNumber = s(.caseNumber, .caseNo)
            cause = s(.cause, .causeName)
            court = s(.court, .courtName)
            levelOfTrial = s(.levelOfTrial, .courtLevelName)
            judgementType = s(.judgementType, .judgementTypeName)
            judgementDate = s(.judgementDate, .judgeDate)
            publishTypeName = s(.publishTypeName, .publishType)
            content = s(.content)
            highlights = s(.highlights)
            timelinessName = s(.timelinessName)
            levelName = s(.levelName)
            publisherName = s(.publisherName)
            issuedNo = s(.issuedNo)
            publishDate = s(.publishDate)
            activeDate = s(.activeDate)
        }
    }
}
