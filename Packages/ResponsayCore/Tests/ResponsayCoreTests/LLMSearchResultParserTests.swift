import Testing
import Foundation
@testable import ResponsayCore

// MARK: - LLMSearchResultParser tests

@Suite("LLMSearchResultParser — unified extraction from provider responses")
struct LLMSearchResultParserTests {

    // MARK: - Kimi (tool_calls response)

    @Test func kimi_parsesToolCallSearchResult() throws {
        let json = """
        {
          "choices": [{
            "message": {
              "content": "根据搜索结果，《中华人民共和国民法典》第577条规定：当事人一方不履行合同义务或者履行合同义务不符合约定的，应当承担继续履行、采取补救措施或者赔偿损失等违约责任。",
              "tool_calls": [{
                "type": "builtin_function",
                "function": {
                  "name": "web_search",
                  "arguments": "{\\"query\\": \\"民法典第577条\\"}"
                }
              }],
              "search_results": [
                {
                  "title": "民法典第577条 - 国家法律法规数据库",
                  "url": "https://flk.npc.gov.cn/detail2.html?ZmY4...",
                  "content": "第五百七十七条　当事人一方不履行合同义务..."
                }
              ]
            }
          }]
        }
        """.data(using: .utf8)!
        let result = try #require(LLMSearchResultParser.parse(responseData: json, providerId: "kimi"))
        #expect(result.title == "民法典第577条 - 国家法律法规数据库")
        #expect(result.url.contains("flk.npc.gov.cn"))
        #expect(result.snippet.contains("五百七十七条"))
        #expect(result.provider == "kimi")
    }

    // MARK: - Qwen (inline citations + content)

    @Test func qwen_parsesInlineCitationResponse() throws {
        let json = """
        {
          "choices": [{
            "message": {
              "content": "《民法典》第577条规定[1]：当事人一方不履行合同义务的，应当承担违约责任。\\n\\n[1] 来源：国家法律法规数据库 https://flk.npc.gov.cn/detail.html?id=abc"
            }
          }]
        }
        """.data(using: .utf8)!
        let result = try #require(LLMSearchResultParser.parse(responseData: json, providerId: "qwen"))
        #expect(result.url.contains("flk.npc.gov.cn"))
        #expect(result.snippet.contains("577"))
        #expect(result.provider == "qwen")
    }

    @Test func qwenResponses_parsesWebSearchCallSources() throws {
        let json = """
        {
          "output": [
            {
              "type": "web_search_call",
              "status": "completed",
              "action": {
                "type": "search",
                "query": "民法典第五百七十七条",
                "sources": [
                  {"type": "url", "url": "https://flk.npc.gov.cn/detail2.html"}
                ]
              }
            },
            {
              "type": "message",
              "content": [{
                "type": "output_text",
                "text": "已检索到《民法典》第五百七十七条。",
                "annotations": []
              }]
            }
          ]
        }
        """.data(using: .utf8)!

        let result = try #require(LLMSearchResultParser.parse(responseData: json, providerId: "qwen"))
        #expect(result.url == "https://flk.npc.gov.cn/detail2.html")
        #expect(result.snippet.contains("民法典"))
        #expect(result.provider == "qwen")
    }

    // MARK: - MiMo (official annotations url_citation)

    @Test func mimo_parsesUrlCitationAnnotations() throws {
        let json = """
        {
          "choices": [{
            "message": {
              "content": "根据搜索结果，武汉明天白天为阴天。",
              "annotations": [{
                "type": "url_citation",
                "url": "https://news.qq.com/rain/a/20260422A03GDF00",
                "title": "小雨转晴再迎小雨!武汉未来三天阴晴交替",
                "summary": "明日武汉天气为阴，夜间晴，最高气温18°C。"
              }]
            }
          }]
        }
        """.data(using: .utf8)!
        let result = try #require(LLMSearchResultParser.parse(responseData: json, providerId: "mimo"))
        #expect(result.title.contains("武汉"))
        #expect(result.url.contains("news.qq.com"))
        #expect(result.snippet.contains("明日武汉"))
        #expect(result.provider == "mimo")
    }

    // MARK: - MiMo legacy fallback (search_results in message)

    @Test func mimo_parsesSearchResults() throws {
        let json = """
        {
          "choices": [{
            "message": {
              "content": "搜索到相关内容：民法典第577条是关于违约责任的规定。",
              "search_results": [{
                "title": "民法典第五百七十七条",
                "url": "https://flk.npc.gov.cn/detail2.html?xyz",
                "content": "当事人一方不履行合同义务..."
              }]
            }
          }]
        }
        """.data(using: .utf8)!
        let result = try #require(LLMSearchResultParser.parse(responseData: json, providerId: "mimo"))
        #expect(result.title == "民法典第五百七十七条")
        #expect(result.url.contains("flk.npc.gov.cn"))
        #expect(result.provider == "mimo")
    }

    // MARK: - Doubao / Ark Responses (web_search plugin)

    @Test func doubao_responsesParsesUrlCitationAnnotations() throws {
        let json = """
        {
          "output": [
            {
              "type": "web_search_call",
              "status": "completed"
            },
            {
              "type": "message",
              "role": "assistant",
              "content": [{
                "type": "output_text",
                "text": "根据搜索结果，《民法典》第577条规定了违约责任。",
                "annotations": [{
                  "type": "url_citation",
                  "url": "https://flk.npc.gov.cn/detail2.html?id=abc",
                  "title": "中华人民共和国民法典",
                  "summary": "第五百七十七条 当事人一方不履行合同义务..."
                }]
              }]
            }
          ]
        }
        """.data(using: .utf8)!
        let result = try #require(LLMSearchResultParser.parse(responseData: json, providerId: "doubao"))
        #expect(result.title == "中华人民共和国民法典")
        #expect(result.url.contains("flk.npc.gov.cn"))
        #expect(result.snippet.contains("五百七十七条"))
        #expect(result.provider == "doubao")
    }

    // MARK: - Not found → nil

    @Test func notFound_returnsNil() {
        let json = """
        {
          "choices": [{
            "message": {
              "content": "很抱歉，我未能找到与案号(2023)京03民终99999号相关的裁判文书。该案号可能尚未公开或不存在。"
            }
          }]
        }
        """.data(using: .utf8)!
        let result = LLMSearchResultParser.parse(responseData: json, providerId: "kimi")
        #expect(result == nil)
    }

    // MARK: - Malformed JSON → nil (not crash)

    @Test func malformedJSON_returnsNil() {
        let json = "not json".data(using: .utf8)!
        let result = LLMSearchResultParser.parse(responseData: json, providerId: "qwen")
        #expect(result == nil)
    }

    @Test func emptyChoices_returnsNil() {
        let json = """
        {"choices": []}
        """.data(using: .utf8)!
        let result = LLMSearchResultParser.parse(responseData: json, providerId: "kimi")
        #expect(result == nil)
    }

    // MARK: - Content-only fallback (URL extraction from plain text)

    @Test func contentOnly_extractsURLFromText() throws {
        let json = """
        {
          "choices": [{
            "message": {
              "content": "根据国家法律法规数据库(https://flk.npc.gov.cn/detail2.html?id=abc)，第577条规定了违约责任。"
            }
          }]
        }
        """.data(using: .utf8)!
        let result = try #require(LLMSearchResultParser.parse(responseData: json, providerId: "qwen"))
        #expect(result.url.contains("flk.npc.gov.cn"))
    }

    // MARK: - Content with no URL and no search_results → nil

    @Test func contentWithoutURL_noSearchResults_returnsNil() {
        let json = """
        {
          "choices": [{
            "message": {
              "content": "民法典第577条是关于违约责任的一般规定。"
            }
          }]
        }
        """.data(using: .utf8)!
        let result = LLMSearchResultParser.parse(responseData: json, providerId: "qwen")
        #expect(result == nil)
    }
}
