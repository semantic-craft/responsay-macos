import Foundation

/// Parses DashScope native `output.search_info.search_results` into the same
/// result shape used by chat-completions search providers.
enum DashScopeSearchResultParser {
    static func parse(
        responseData: Data,
        providerId: String,
        kind: VerificationKind? = nil
    ) -> LLMSearchResultParser.SearchResult? {
        guard let root = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let output = root["output"] as? [String: Any],
              let searchInfo = output["search_info"] as? [String: Any],
              let results = searchInfo["search_results"] as? [[String: Any]] else {
            return nil
        }
        let content = assistantContent(from: output)
        return results
            .compactMap { result(from: $0, providerId: providerId, snippet: content, kind: kind) }
            .sorted { $0.score > $1.score }
            .first?
            .result
    }

    private static func assistantContent(from output: [String: Any]) -> String {
        guard let choices = output["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            return ""
        }
        return String(content.prefix(240))
    }

    private static func result(
        from raw: [String: Any],
        providerId: String,
        snippet: String,
        kind: VerificationKind?
    ) -> (score: Int, result: LLMSearchResultParser.SearchResult)? {
        let url = raw["url"] as? String ?? raw["link"] as? String ?? ""
        guard !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let title = raw["title"] as? String ?? raw["site_name"] as? String ?? "搜索结果"
        let item = LLMSearchResultParser.SearchResult(
            title: title,
            url: url,
            snippet: snippet,
            provider: providerId)
        return (score(url: url, title: title, kind: kind), item)
    }

    private static func score(url: String, title: String, kind: VerificationKind?) -> Int {
        let u = url.lowercased()
        let t = title.lowercased()
        var score = 10
        if u.contains(".gov.cn") || u.contains("court.gov.cn") { score += 20 }
        if t.contains("官方") || t.contains("数据库") { score += 8 }

        switch kind {
        case .law, .administrativeRule, .officialDocument, .standard:
            if u.contains("flk.npc.gov.cn") { score += 100 }
            if u.contains("pkulaw.com") { score += 45 }
            if u.contains("gov.cn") { score += 35 }
        case .caseLaw:
            if u.contains("rmfyalk.court.gov.cn") { score += 100 }
            if u.contains("wenshu.court.gov.cn") { score += 85 }
            if u.contains("court.gov.cn") { score += 70 }
            if u.contains("pkulaw.com") { score += 45 }
            if u.contains("itslaw.com") { score += 35 }
        case .scholarlyArticle:
            if u.contains("cnki.net") { score += 100 }
            if u.contains("wanfangdata") { score += 80 }
            if u.contains("cqvip.com") { score += 70 }
        default:
            break
        }
        if u.contains("baijiahao") || u.contains("zhihu.com") || u.contains("sohu.com") {
            score -= 20
        }
        return score
    }
}
