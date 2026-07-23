import Foundation

// MARK: - 488 找类案搜索结果解析
//
// The 找类案 search-LLM (qwenSearch) returns candidate cases as JSON; this turns that raw
// text into `[CaseCandidate]` for `CaseCandidateScreener`. Lenient: strips ```json fences,
// takes the first {…} object, returns [] on anything malformed (the screener then shows
// nothing rather than crashing). The LLM may hallucinate — that's the screener's job to gate.

public enum CaseCandidateSearchParser {
    /// Instruction for the 找类案 search call: ask for real candidates as the JSON shape this
    /// parser reads, with case numbers + sources, and an explicit "未找到→空" escape so the
    /// model isn't pushed to fabricate. The screener gates whatever comes back.
    public static func prompt(query: String) -> String {
        """
        请用联网搜索，围绕以下法律问题/争议焦点，找出**真实存在**的类案（裁判文书或两高典型案例）：

        \(query)

        严格要求：
        1. 只返回 JSON，不要任何解释文字。形如：
        {"candidates": [{"title": "案件标题", "summary": "含完整案号的简述，如（2023）X0000民初0号……", "sources": ["来源URL"], "typical": false}]}
        2. `summary` 必须包含你检索到的**完整案号**；两高典型案例无文书案号时 `typical` 置 true。
        3. `sources` 填你实际检索到的来源网址；没有就留空数组。
        4. **绝不编造**案例、案号或来源。检索不到就返回 {"candidates": []}。
        """
    }

    private struct Payload: Decodable {
        let candidates: [Item]
        struct Item: Decodable {
            let title: String?
            let summary: String?
            let sources: [String]?
            let typical: Bool?
        }
    }

    public static func parse(_ raw: String) -> [CaseCandidate] {
        guard let json = firstJSONObject(in: raw),
              let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return [] }
        return payload.candidates.map { item in
            CaseCandidate(
                title: item.title ?? "",
                text: item.summary ?? "",
                sourceURLs: item.sources ?? [],
                isTypicalCase: item.typical ?? false)
        }
    }

    /// First `{ … }` block (brace-balanced), tolerating ```json fences / prose around it.
    private static func firstJSONObject(in raw: String) -> String? {
        guard let start = raw.firstIndex(of: "{") else { return nil }
        var depth = 0
        var idx = start
        while idx < raw.endIndex {
            let ch = raw[idx]
            if ch == "{" { depth += 1 }
            else if ch == "}" {
                depth -= 1
                if depth == 0 { return String(raw[start...idx]) }
            }
            idx = raw.index(after: idx)
        }
        return nil
    }
}
