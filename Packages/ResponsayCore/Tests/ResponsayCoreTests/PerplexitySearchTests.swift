import Testing
import Foundation
@testable import ResponsayCore

// Perplexity 走的是 `/search` 纯检索(不是 sonar 作答模型):请求 `{query, max_results}`,
// 响应 `{results:[{title,url,snippet,date,last_updated}]}`。date 经常是 null,要退到 last_updated。

@Suite struct PerplexitySearchTests {

    private func body(_ request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func makeRequest_targetsSearchEndpointWithBearerAuth() throws {
        let request = try PerplexitySearchRequestBuilder.makeRequest(
            apiKey: "pplx-test", query: "latest AI developments", maxResults: 5)
        #expect(request.url?.absoluteString == "https://api.perplexity.ai/search")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer pplx-test")
        let payload = try body(request)
        #expect(payload["query"] as? String == "latest AI developments")
        #expect(payload["max_results"] as? Int == 5)
    }

    @Test func makeRequest_clampsMaxResults() throws {
        let high = try body(try PerplexitySearchRequestBuilder.makeRequest(
            apiKey: "k", query: "q", maxResults: 999))
        #expect(high["max_results"] as? Int == 20)
    }

    @Test func makeRequest_rejectsMissingKey() {
        #expect(throws: WebSearchError.notConfigured) {
            try PerplexitySearchRequestBuilder.makeRequest(apiKey: "", query: "q", maxResults: 5)
        }
    }

    @Test func parse_mapsResults() throws {
        let documents = try PerplexitySearchResultParser.parse(Data("""
        {"id":"abc","results":[
          {"title":"Example","url":"https://example.com/a","snippet":"An excerpt.","date":"2026-01-23","last_updated":"2026-09-25"}]}
        """.utf8))
        #expect(documents.count == 1)
        #expect(documents[0].title == "Example")
        #expect(documents[0].snippet == "An excerpt.")
        #expect(documents[0].publishTime == "2026-01-23")
        #expect(documents[0].hostname.isEmpty)   // Perplexity 不给站点名
    }

    /// 站点没标发布时间时 date 是 null;有个 last_updated 总比时间戳全空强。
    @Test func parse_fallsBackToLastUpdatedWhenDateIsNull() throws {
        let documents = try PerplexitySearchResultParser.parse(Data("""
        {"results":[{"title":"t","url":"https://e.com","snippet":"","date":null,"last_updated":"2026-05-20"}]}
        """.utf8))
        #expect(documents[0].publishTime == "2026-05-20")
    }

    @Test func parse_dropsResultsWithoutURL() throws {
        let documents = try PerplexitySearchResultParser.parse(Data("""
        {"results":[{"title":"no url"},{"title":"ok","url":"https://e.com"}]}
        """.utf8))
        #expect(documents.map(\.url) == ["https://e.com"])
    }

    @Test func parse_surfacesErrorEnvelope() {
        #expect(throws: WebSearchError.self) {
            try PerplexitySearchResultParser.parse(Data("""
            {"error":{"type":"invalid_api_key","message":"Invalid API key"}}
            """.utf8))
        }
    }
}
