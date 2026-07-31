import Foundation

/// 解析「豆包搜索 Global 版」响应。响应是火山系的两层信封:
/// `ResponseMetadata`(含接口层 `Error`)+ `Result`(含业务层 `ErrorCode` / `Documents`)。
/// 两层都可能报错,都要认。
enum DoubaoSearchResultParser {

    static func parse(_ data: Data) throws -> [WebSearchDocument] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WebSearchError.badResponse("响应不是 JSON 对象")
        }

        // 接口层错误(鉴权、参数、限流)。Result 此时为 null。
        if let metadata = root["ResponseMetadata"] as? [String: Any],
           let error = metadata["Error"] as? [String: Any] {
            throw providerError(code: error["Code"], codeN: error["CodeN"], message: error["Message"])
        }

        guard let result = root["Result"] as? [String: Any] else {
            throw WebSearchError.badResponse("响应缺少 Result")
        }

        // 业务层错误码。0 = 正常。
        let errorCode = result["ErrorCode"] as? Int ?? 0
        if errorCode != 0 {
            throw providerError(code: nil, codeN: errorCode, message: result["ErrorMsg"])
        }

        let documents = result["Documents"] as? [[String: Any]] ?? []
        return documents.compactMap(document(from:))
    }

    // MARK: - Documents

    private static func document(from raw: [String: Any]) -> WebSearchDocument? {
        let url = (raw["Url"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return nil }   // 没有落地页的结果引不了,丢掉
        let info = raw["DocumentInfo"] as? [String: Any]
        let host = raw["HostInfo"] as? [String: Any]
        return WebSearchDocument(
            title: raw["Title"] as? String ?? "",
            url: url,
            snippet: textSnippet(raw["Snippet"] as? [[String: Any]] ?? []),
            hostname: host?["Hostname"] as? String ?? "",
            publishTime: info?["PublishTime"] as? String ?? "")
    }

    /// `Snippet` 是 text / image 混排的数组。我们只喂文字给模型,图片片段直接跳过
    /// (接口没法关掉配图,`MaxImageCountPerDoc` 只能调数量)。
    static func textSnippet(_ snippets: [[String: Any]]) -> String {
        snippets
            .filter { ($0["Type"] as? String) == "text" }
            .compactMap { $0["Text"] as? String }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Errors

    private static func providerError(code: Any?, codeN: Any?, message: Any?) -> WebSearchError {
        let resolved = (code as? String) ?? (codeN as? Int).map(String.init) ?? "未知"
        let raw = (message as? String) ?? ""
        let hint = hint(for: resolved)
        let text = [raw, hint].filter { !$0.isEmpty }.joined(separator: " — ")
        return .provider(code: resolved, message: text.isEmpty ? "搜索失败" : text)
    }

    /// 文档「错误处理」表里用户真会撞上的那几条,翻成能照做的一句话。
    /// 其余错误码原样透传服务商的 Message。
    static func hint(for code: String) -> String {
        switch code {
        case "10403", "10408": return "检查 API Key、账号信息和豆包搜索的开通状态"
        case "10409", "10410": return "豆包搜索 Global 版只支持按量后付费,请在联网搜索控制台开通"
        case "10412":          return "套餐额度不足"
        case "700429":         return "请求过于频繁(账号默认 5 QPS),稍后再试"
        case "700901":         return "API Key 无效,确认填的是联网搜索控制台签发的 Key(不是方舟的)"
        default:               return ""
        }
    }
}
