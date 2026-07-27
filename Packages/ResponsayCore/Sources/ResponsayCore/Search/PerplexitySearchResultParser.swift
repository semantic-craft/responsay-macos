import Foundation

/// 解析 Perplexity `/search` 响应:`{ "id": …, "results": [{title, url, snippet, date, last_updated}] }`。
/// 错误走 HTTP 状态码(由 `HTTPWebSearchBackend` 拦),响应体本身没有业务错误码信封。
enum PerplexitySearchResultParser {

    static func parse(_ data: Data) throws -> [WebSearchDocument] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WebSearchError.badResponse("响应不是 JSON 对象")
        }
        guard let results = root["results"] as? [[String: Any]] else {
            // 有 error 字段的话原样带出来,比「缺 results」有用。
            if let error = root["error"] as? [String: Any], let message = error["message"] as? String {
                throw WebSearchError.provider(code: error["type"] as? String ?? "error", message: message)
            }
            throw WebSearchError.badResponse("响应缺少 results")
        }
        return results.compactMap(document(from:))
    }

    private static func document(from raw: [String: Any]) -> WebSearchDocument? {
        let url = (raw["url"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return nil }
        // date 常为 null(站点没标发布时间),此时退到 last_updated——有个时间戳总比没有强。
        let published = raw["date"] as? String ?? raw["last_updated"] as? String ?? ""
        return WebSearchDocument(
            title: raw["title"] as? String ?? "",
            url: url,
            snippet: (raw["snippet"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            hostname: "",   // Perplexity 不返回站点名;展示时由 URL 自己说明
            publishTime: published)
    }
}
