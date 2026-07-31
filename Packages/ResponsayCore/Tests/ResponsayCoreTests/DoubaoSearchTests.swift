import Testing
import Foundation
@testable import ResponsayCore

// 豆包搜索 Global 版是一套独立于方舟的接口:自己的域名、Bearer 鉴权、火山系两层响应信封。
// 请求侧要盯住文档的硬约束(Query ≤100 字符、DocCount ≤20);响应侧要盯住两层错误
// (ResponseMetadata.Error / Result.ErrorCode)和 text+image 混排的摘要。

@Suite struct DoubaoSearchRequestBuilderTests {

    private func body(_ request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func makeRequest_targetsGlobalSearchWithBearerAuth() throws {
        let request = try DoubaoSearchRequestBuilder.makeRequest(
            apiKey: "sk-test", query: "北京周边游玩景点推荐", docCount: 5)
        #expect(request.url?.absoluteString == "https://open.feedcoopapi.com/search_api/global_search")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let payload = try body(request)
        #expect(payload["Query"] as? String == "北京周边游玩景点推荐")
        #expect(payload["DocCount"] as? Int == 5)
        #expect(payload["MaxSnippetLength"] as? Int == 500)
    }

    /// 文档:Query 1~100 字符,过长会被接口截断——截在我们这边,送出去的才是可预期的。
    @Test func makeRequest_capsQueryAtHundredCharacters() throws {
        let long = String(repeating: "查", count: 250)
        let payload = try body(try DoubaoSearchRequestBuilder.makeRequest(
            apiKey: "sk", query: long, docCount: 5))
        #expect((payload["Query"] as? String)?.count == 100)
    }

    @Test func makeRequest_clampsDocCountIntoLegalRange() throws {
        let high = try body(try DoubaoSearchRequestBuilder.makeRequest(apiKey: "sk", query: "q", docCount: 99))
        #expect(high["DocCount"] as? Int == 20)
        let low = try body(try DoubaoSearchRequestBuilder.makeRequest(apiKey: "sk", query: "q", docCount: 0))
        #expect(low["DocCount"] as? Int == 1)
    }

    @Test func makeRequest_rejectsMissingKeyOrQuery() {
        #expect(throws: WebSearchError.notConfigured) {
            try DoubaoSearchRequestBuilder.makeRequest(apiKey: "  ", query: "q", docCount: 5)
        }
        #expect(throws: WebSearchError.notConfigured) {
            try DoubaoSearchRequestBuilder.makeRequest(apiKey: "sk", query: "   ", docCount: 5)
        }
    }
}

@Suite struct DoubaoSearchResultParserTests {

    private func data(_ json: String) -> Data { Data(json.utf8) }

    @Test func parse_mapsDocumentsWithHostAndPublishTime() throws {
        let documents = try DoubaoSearchResultParser.parse(data("""
        {"ResponseMetadata":{"RequestId":"r1"},
         "Result":{"TotalDocCount":20,"ErrorCode":0,"ErrorMsg":"","Documents":[
           {"Rank":0,"Url":"https://example.com/a","Title":"天安门",
            "Snippet":[{"Type":"text","Text":"天安门是紫禁城的重要建筑。"}],
            "DocumentInfo":{"Filetype":"webpage","PublishTime":"2026-06-01"},
            "HostInfo":{"Hostname":"抖音百科","IconUrl":"https://icon"}}]}}
        """))
        #expect(documents.count == 1)
        #expect(documents[0].title == "天安门")
        #expect(documents[0].url == "https://example.com/a")
        #expect(documents[0].snippet == "天安门是紫禁城的重要建筑。")
        #expect(documents[0].hostname == "抖音百科")
        #expect(documents[0].publishTime == "2026-06-01")
    }

    /// 摘要是 text / image 混排。图片喂给模型没有意义,而且接口关不掉配图,只能这边跳过。
    @Test func parse_keepsOnlyTextSnippetSegments() throws {
        let documents = try DoubaoSearchResultParser.parse(data("""
        {"Result":{"ErrorCode":0,"Documents":[
          {"Url":"https://e.com","Title":"t","Snippet":[
            {"Type":"text","Text":"前段。"},
            {"Type":"image","Image":{"Width":1,"Height":2,"ImageUrl":"https://img"}},
            {"Type":"text","Text":"后段。"}]}]}}
        """))
        #expect(documents[0].snippet == "前段。后段。")
    }

    @Test func parse_dropsDocumentsWithoutURL() throws {
        let documents = try DoubaoSearchResultParser.parse(data("""
        {"Result":{"ErrorCode":0,"Documents":[{"Title":"无落地页"},{"Url":"https://ok","Title":"有"}]}}
        """))
        #expect(documents.map(\.url) == ["https://ok"])
    }

    /// 接口层错误:HTTP 200,错误藏在 ResponseMetadata.Error 里,Result 为 null。
    @Test func parse_surfacesInterfaceLevelError() {
        #expect(throws: WebSearchError.self) {
            try DoubaoSearchResultParser.parse(data("""
            {"ResponseMetadata":{"RequestId":"r","Error":{"CodeN":10400,"Code":"10400","Message":"query is empty"}},
             "Result":null}
            """))
        }
    }

    /// 无效 Key 是用户最常撞的一条,错误里必须带上「填错了哪把 Key」的提示。
    @Test func parse_invalidKeyErrorCarriesActionableHint() {
        do {
            _ = try DoubaoSearchResultParser.parse(data("""
            {"ResponseMetadata":{"Error":{"Code":"700901","Message":"invalid api key"}},"Result":null}
            """))
            Issue.record("应当抛错")
        } catch let error as WebSearchError {
            guard case .provider(let code, let message) = error else {
                Issue.record("应当是 provider 错误,实际 \(error)")
                return
            }
            #expect(code == "700901")
            #expect(message.contains("联网搜索控制台"))
        } catch {
            Issue.record("意外错误 \(error)")
        }
    }

    /// 业务层错误码在 Result 里,和接口层是两处,都要认。
    @Test func parse_surfacesResultLevelErrorCode() {
        do {
            _ = try DoubaoSearchResultParser.parse(data("""
            {"ResponseMetadata":{},"Result":{"ErrorCode":10412,"ErrorMsg":"quota exhausted","Documents":[]}}
            """))
            Issue.record("应当抛错")
        } catch let error as WebSearchError {
            guard case .provider(let code, _) = error else {
                Issue.record("应当是 provider 错误,实际 \(error)")
                return
            }
            #expect(code == "10412")
        } catch {
            Issue.record("意外错误 \(error)")
        }
    }

    /// 搜不到 ≠ 出错:0 条是合法结果,由调用方决定退回不带检索的作答。
    @Test func parse_emptyDocumentsIsNotAnError() throws {
        let documents = try DoubaoSearchResultParser.parse(data(#"{"Result":{"ErrorCode":0,"Documents":[]}}"#))
        #expect(documents.isEmpty)
    }
}
