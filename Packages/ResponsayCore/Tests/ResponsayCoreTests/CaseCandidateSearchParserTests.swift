import Testing
@testable import ResponsayCore

@Suite("488 · 找类案搜索结果解析（LLM JSON → 候选）")
struct CaseCandidateSearchParserTests {

    @Test("规整 JSON → 候选列表（含案号文本 + 来源 + 两高标记）")
    func parsesWellFormedCandidates() {
        let raw = """
        {"candidates": [
          {"title": "竞业限制案", "summary": "（2023）沪0115民初1234号，法院认为……", "sources": ["https://wenshu.court.gov.cn/a"], "typical": false},
          {"title": "最高法典型案例", "summary": "无文书案号的典型案例", "sources": ["https://www.court.gov.cn/t/1"], "typical": true}
        ]}
        """
        let out = CaseCandidateSearchParser.parse(raw)
        #expect(out.count == 2)
        #expect(out.first?.text.contains("民初1234号") == true)
        #expect(out.first?.sourceURLs == ["https://wenshu.court.gov.cn/a"])
        #expect(out.last?.isTypicalCase == true)
    }

    @Test("乱码 / 非 JSON → 空列表（screener 不展示，不崩）")
    func malformedYieldsEmpty() {
        #expect(CaseCandidateSearchParser.parse("未找到相关案例。").isEmpty)
        #expect(CaseCandidateSearchParser.parse("").isEmpty)
    }

    @Test("```json 围栏 + 前后散文 → 仍解析出候选")
    func parsesFencedJSON() {
        let raw = """
        我搜索到以下候选：
        ```json
        {"candidates": [{"title": "x", "summary": "（2022）粤01民终5号", "sources": [], "typical": false}]}
        ```
        以上仅供参考。
        """
        #expect(CaseCandidateSearchParser.parse(raw).count == 1)
    }
}
