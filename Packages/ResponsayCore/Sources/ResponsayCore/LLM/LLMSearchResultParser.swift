import Foundation

// MARK: - LLMSearchResultParser
//
// Parses web-search results from LLM chat completion responses into a unified
// `VerifiedSource`. Each provider embeds search results differently:
// - MiMo: `annotations` array with `url_citation` entries
// - Doubao/Ark Responses: `output[].content[].annotations`
// - Kimi/legacy MiMo: `search_results` array in the message object
// - Zhipu: `web_search` array in the message object
// - Qwen: inline `[ref]` citations in content text + sometimes metadata
// - Fallback: extract URL from plain content text
//
// Returns nil when the LLM searched but found nothing (搜不到 ≠ 不存在).

public enum LLMSearchResultParser {

    public struct SearchResult: Sendable, Equatable {
        public let title: String
        public let url: String
        public let snippet: String
        public let provider: String
    }

    /// Parse a raw chat completion response and extract the first verified source.
    /// Returns nil when no actionable source was found (not an error — just "not found").
    public static func parse(responseData: Data, providerId: String) -> SearchResult? {
        guard let root = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            return nil
        }

        if let responsesResult = parseResponsesOutput(root, providerId: providerId) {
            return responsesResult
        }

        guard let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else {
            return nil
        }

        // Try official OpenAI-style URL citations first (MiMo web_search)
        if let result = parseAnnotations(message, providerId: providerId) {
            return result
        }

        // Try structured search results next (Kimi, legacy MiMo shapes)
        if let result = parseSearchResults(message, providerId: providerId) {
            return result
        }

        // Try Zhipu's web_search field
        if let result = parseWebSearch(message, providerId: providerId) {
            return result
        }

        // Fallback: extract URL from content text
        if let content = message["content"] as? String {
            return parseContentFallback(content, providerId: providerId)
        }

        return nil
    }

    // MARK: - OpenAI-style annotations (MiMo url_citation)

    private static func parseAnnotations(_ message: [String: Any], providerId: String) -> SearchResult? {
        guard let annotations = message["annotations"] as? [[String: Any]] else {
            return nil
        }
        let fallback = message["content"] as? String ?? message["text"] as? String ?? ""
        return parseAnnotationList(annotations, providerId: providerId, fallbackSnippet: fallback)
    }

    private static func parseAnnotationList(
        _ annotations: [[String: Any]],
        providerId: String,
        fallbackSnippet: String
    ) -> SearchResult? {
        guard let first = annotations.first(where: { ($0["url"] as? String)?.isEmpty == false }) else {
            return nil
        }
        let title = first["title"] as? String ?? ""
        let url = first["url"] as? String ?? ""
        let snippet = first["summary"] as? String ?? first["content"] as? String ?? fallbackSnippet
        guard !url.isEmpty else { return nil }
        return SearchResult(title: title, url: url, snippet: snippet, provider: providerId)
    }

    // MARK: - Ark Responses output

    private static func parseResponsesOutput(_ root: [String: Any], providerId: String) -> SearchResult? {
        guard let output = root["output"] as? [[String: Any]] else { return nil }
        var fallbackText = ""

        for item in output {
            if let result = parseSearchResults(item, providerId: providerId) {
                return result
            }
            if let result = parseWebSearch(item, providerId: providerId) {
                return result
            }
            guard let content = item["content"] as? [[String: Any]] else { continue }
            for part in content {
                let text = part["text"] as? String ?? ""
                if !text.isEmpty { fallbackText += text + "\n" }
                if let annotations = part["annotations"] as? [[String: Any]],
                   let result = parseAnnotationList(
                    annotations,
                    providerId: providerId,
                    fallbackSnippet: text.isEmpty ? fallbackText : text
                   ) {
                    return result
                }
            }
        }

        return fallbackText.isEmpty ? nil : parseContentFallback(fallbackText, providerId: providerId)
    }

    // MARK: - Structured search_results (Kimi, legacy MiMo)

    private static func parseSearchResults(_ message: [String: Any], providerId: String) -> SearchResult? {
        guard let results = message["search_results"] as? [[String: Any]],
              let first = results.first else { return nil }
        let title = first["title"] as? String ?? ""
        let url = first["url"] as? String ?? first["link"] as? String ?? ""
        let snippet = first["content"] as? String ?? ""
        guard !url.isEmpty else { return nil }
        return SearchResult(title: title, url: url, snippet: snippet, provider: providerId)
    }

    // MARK: - Zhipu web_search field

    private static func parseWebSearch(_ message: [String: Any], providerId: String) -> SearchResult? {
        guard let results = message["web_search"] as? [[String: Any]],
              let first = results.first else { return nil }
        let title = first["title"] as? String ?? ""
        let url = first["link"] as? String ?? first["url"] as? String ?? ""
        let snippet = first["content"] as? String ?? ""
        guard !url.isEmpty else { return nil }
        return SearchResult(title: title, url: url, snippet: snippet, provider: providerId)
    }

    // MARK: - Content fallback: extract first URL from text

    private static let urlPattern = try! NSRegularExpression(
        pattern: #"https?://[^\s\)\]）」，。、；,;]+"#)

    private static func parseContentFallback(_ content: String, providerId: String) -> SearchResult? {
        let range = NSRange(content.startIndex..., in: content)
        guard let match = urlPattern.firstMatch(in: content, range: range),
              let urlRange = Range(match.range, in: content) else {
            return nil
        }
        let url = String(content[urlRange])
        let snippet = String(content.prefix(200))
        return SearchResult(
            title: extractTitleHint(from: content, url: url),
            url: url,
            snippet: snippet,
            provider: providerId)
    }

    private static func extractTitleHint(from content: String, url: String) -> String {
        if url.contains("flk.npc.gov.cn") { return "国家法律法规数据库" }
        if url.contains("pkulaw.com") { return "北大法宝" }
        if url.contains("itslaw.com") { return "无讼" }
        if url.contains("cnki.net") { return "知网" }
        if url.contains("wanfangdata") { return "万方" }
        if url.contains("cqvip.com") { return "维普" }
        if url.contains("court.gov.cn") { return "裁判文书网" }
        return "搜索结果"
    }
}
