import Foundation
import Testing
@testable import ResponsayCore

@Suite("Qwen Token Plan LLM route")
struct QwenTokenPlanLLMTests {
    private let baseURL = "https://token-plan.cn-beijing.maas.aliyuncs.com/compatible-mode/v1"
    private let host = "token-plan.cn-beijing.maas.aliyuncs.com"

    @Test func capabilitiesMirrorBailianQwenPayAsYouGoStrategy() {
        let caps = LLMProviderCapabilities.resolve(providerId: "qwen-token-plan", baseURLHost: host)

        #expect(caps.supportsChatCompletions)
        #expect(!caps.supportsResponses)
        #expect(caps.supportsStreamUsage)
        #expect(caps.supportsBatch)
        #expect(caps.builtinTools.contains(.webSearch))
        #expect(caps.authHeaderStyle == .bearer)
        #expect(caps.thinkingControl == .enableThinking)
    }

    @Test func requestUsesTokenPlanEndpointFlashDefaultAndPlainRewriteShape() throws {
        let endpoint = LLMEndpoint(
            providerId: "qwen-token-plan",
            baseURL: baseURL,
            model: "qwen3.6-flash",
            apiKey: "token-plan-key",
            thinkingEnabled: false)

        let request = try LLMChatRequestBuilder.makeRequest(endpoint: endpoint, system: "SYS", user: "USR")

        #expect(request.url?.absoluteString == "\(baseURL)/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token-plan-key")

        let body = try #require(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        #expect(body["model"] as? String == "qwen3.6-flash")
        #expect(body["stream"] as? Bool == false)
        #expect(body["temperature"] as? Double == 0.2)
        #expect(body["top_p"] as? Double == 0.8)
        #expect(body["enable_thinking"] as? Bool == false)

        for field in ["tools", "tool_choice", "enable_search", "mcp", "input", "instructions", "reasoning"] {
            #expect(body[field] == nil)
        }
    }

    @Test func thinkingAndStreamingOptionsFollowQwenCompatibleModeRules() {
        let nonStreaming = LLMThinkingControl.extraBody(
            providerId: "qwen-token-plan",
            model: "qwen3.6-flash",
            baseURLHost: host,
            enabled: true,
            streaming: false)
        let streaming = LLMThinkingControl.extraBody(
            providerId: "qwen-token-plan",
            model: "qwen3.6-flash",
            baseURLHost: host,
            enabled: true,
            streaming: true)
        let streamOptions = LLMStreamOptionsControl.extraBody(providerId: "qwen-token-plan", baseURLHost: host)

        #expect(nonStreaming["enable_thinking"] as? Bool == false)
        #expect(streaming["enable_thinking"] as? Bool == true)
        #expect((streamOptions["stream_options"] as? [String: Bool])?["include_usage"] == true)
    }

    @Test func webSearchIsAvailableButNativeSourceResultsStayDashScopeOnly() {
        #expect(LLMSearchControl.supportsSearch(providerId: "qwen-token-plan", baseURLHost: host))
        #expect(!LLMSearchControl.supportsSourceResults(providerId: "qwen-token-plan", baseURLHost: host))
        #expect(LLMSearchControl.extraBody(
            providerId: "qwen-token-plan",
            baseURLHost: host,
            searchEnabled: true)["enable_search"] as? Bool == true)
        #expect(DashScopeSearchRequestBuilder.generationURL(base: baseURL) == nil)
    }
}
