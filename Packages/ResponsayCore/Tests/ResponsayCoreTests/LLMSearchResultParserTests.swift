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

    // MARK: - DeepSeek Responses (no action.sources — falls back to the URL in the prose)

    /// 实测形状（2026-07-31，deepseek-v4-flash + 服务端 web_search）：DeepSeek 的
    /// `web_search_call.action` 只有 `{type:search, queries:[…]}`（无 URL）或
    /// `{type:open_page, url:"…#ws_call_id=…"}`（常见 status:failed），**没有** Qwen 的
    /// `action.sources`。所以来源只能从正文兜底取——这条链路必须保持有效，否则 DeepSeek
    /// 的 [待核] 核验会一直空手而归。
    @Test func deepseekResponses_noActionSources_fallsBackToProseURL() throws {
        let json = """
        {
          "output": [
            {"type": "web_search_call", "status": "completed",
             "action": {"type": "search", "queries": ["民法典第五百七十七条", "ws_call_id=call_00"]}},
            {"type": "web_search_call", "status": "failed",
             "action": {"type": "open_page", "url": "https://example.invalid/x#ws_call_id=call_01"}},
            {"type": "message",
             "content": [{"type": "output_text",
                          "text": "依据《民法典》第五百七十七条，见 https://flk.npc.gov.cn/detail2.html 。"}]}
          ]
        }
        """.data(using: .utf8)!

        let result = try #require(LLMSearchResultParser.parse(responseData: json, providerId: "deepseek"))
        // 正文里的真链接胜出——不能拿抓取失败的 open_page URL（还挂着 ws_call_id 尾巴）当来源。
        #expect(result.url == "https://flk.npc.gov.cn/detail2.html")
        #expect(!result.url.contains("ws_call_id"))
        #expect(result.provider == "deepseek")
    }

    /// 搜了但正文里没有链接 → nil，不是编一个。搜不到 ≠ 不存在。
    @Test func deepseekResponses_searchedButNoURL_returnsNil() {
        let json = """
        {
          "output": [
            {"type": "web_search_call", "status": "completed",
             "action": {"type": "search", "queries": ["查无此条"]}},
            {"type": "message", "content": [{"type": "output_text", "text": "没有找到相关条文。"}]}
          ]
        }
        """.data(using: .utf8)!
        #expect(LLMSearchResultParser.parse(responseData: json, providerId: "deepseek") == nil)
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
