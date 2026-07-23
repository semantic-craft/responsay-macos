import Testing
@testable import ResponsayCore

/// The OpenAI-vs-Ark body branch is the only non-trivial logic in the shared Responses builder:
/// OpenAI must NOT carry Ark's `thinking` field or the Volcengine-only `max_keyword`/`limit`/
/// `max_tool_calls` (they 400 on OpenAI); Ark must keep them.
struct ArkResponsesSearchRequestBuilderTests {
    typealias B = ArkResponsesSearchRequestBuilder

    @Test func supportsWebSearchRecognizesOpenAIAndArk() {
        #expect(B.supportsWebSearch(providerId: "openai", baseURLHost: "api.openai.com"))
        #expect(B.supportsWebSearch(providerId: "custom", baseURLHost: "api.openai.com"))
        #expect(B.supportsWebSearch(providerId: "doubao", baseURLHost: "ark.cn-beijing.volces.com"))
        #expect(!B.supportsWebSearch(providerId: "qwen", baseURLHost: "dashscope.aliyuncs.com"))
    }

    @Test func openAIBodyDropsThinkingAndToolExtras() {
        let body = B.responsesBody(
            model: "chat-latest", input: [], stream: true,
            thinkingEnabled: true, searchEnabled: true, isOpenAI: true)
        #expect(body["thinking"] == nil)
        #expect(body["max_tool_calls"] == nil)
        let tool = (body["tools"] as? [[String: Any]])?.first
        #expect(tool?["type"] as? String == "web_search")
        #expect(tool?["max_keyword"] == nil)
    }

    @Test func arkBodyKeepsThinkingAndToolExtras() {
        let body = B.responsesBody(
            model: "doubao-seed", input: [], stream: false,
            thinkingEnabled: false, searchEnabled: true, isOpenAI: false)
        #expect((body["thinking"] as? [String: Any])?["type"] as? String == "disabled")
        #expect(body["max_tool_calls"] as? Int == 3)
        let tool = (body["tools"] as? [[String: Any]])?.first
        #expect(tool?["max_keyword"] as? Int == 2)
    }

    @Test func searchDisabledOmitsTools() {
        let body = B.responsesBody(
            model: "chat-latest", input: [], stream: true,
            thinkingEnabled: false, searchEnabled: false, isOpenAI: true)
        #expect(body["tools"] == nil)
    }
}
