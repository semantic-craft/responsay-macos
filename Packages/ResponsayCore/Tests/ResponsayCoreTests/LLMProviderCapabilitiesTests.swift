import Foundation
import Testing
@testable import ResponsayCore

struct LLMProviderCapabilitiesTests {
    @Test func qwenCapabilitiesExposeFastChatStreamingUsageAndToolsButNoResponses() {
        let caps = LLMProviderCapabilities.resolve(providerId: "qwen", baseURLHost: "dashscope.aliyuncs.com")

        #expect(caps.supportsChatCompletions)
        #expect(!caps.supportsResponses)
        #expect(caps.supportsStreamUsage)
        #expect(caps.supportsBatch)
        #expect(caps.builtinTools.contains(.webSearch))
        #expect(caps.authHeaderStyle == .bearer)
    }

    @Test func mimoCapabilitiesUseApiKeyAuthAndDisableResponsesOnlyFeatures() {
        let caps = LLMProviderCapabilities.resolve(providerId: "mimo", baseURLHost: "api.xiaomimimo.com")

        #expect(caps.supportsChatCompletions)
        #expect(caps.authHeaderStyle == .apiKeyHeader("api-key"))
        #expect(caps.thinkingControl == .thinkingObject)
        #expect(!caps.supportsResponses)
        #expect(caps.builtinTools.contains(.webSearch))
    }

    @Test func zhipuAndGeminiCapabilitiesExposeTheirThinkingControls() {
        let zhipu = LLMProviderCapabilities.resolve(providerId: "zhipu", baseURLHost: "open.bigmodel.cn")
        #expect(zhipu.supportsThinkingControl)
        #expect(zhipu.thinkingControl == .thinkingObject)
        #expect(!zhipu.supportsResponses)

        let gemini = LLMProviderCapabilities.resolve(
            providerId: "gemini",
            baseURLHost: "generativelanguage.googleapis.com")
        #expect(gemini.supportsThinkingControl)
        #expect(gemini.thinkingControl == .reasoningEffort)
        #expect(!gemini.supportsResponses)
    }

    @Test func doubaoCapabilitiesUseArkBearerResponsesSearchThinkingAndStreamUsage() {
        let caps = LLMProviderCapabilities.resolve(providerId: "doubao", baseURLHost: "ark.cn-beijing.volces.com")

        #expect(caps.supportsChatCompletions)
        #expect(caps.supportsResponses)
        #expect(caps.supportsStreamUsage)
        #expect(caps.supportsThinkingControl)
        #expect(caps.thinkingControl == .thinkingObject)
        #expect(caps.builtinTools.contains(.webSearch))
        #expect(caps.authHeaderStyle == .bearer)
        #expect(caps.allowsGenerationParameters)
    }

    @Test func unknownCustomEndpointIsConservative() {
        let caps = LLMProviderCapabilities.resolve(providerId: "custom", baseURLHost: "llm.example.test")

        #expect(caps.supportsChatCompletions)
        #expect(!caps.supportsResponses)
        #expect(!caps.supportsStreamUsage)
        #expect(!caps.supportsJSONMode)
        #expect(caps.builtinTools.isEmpty)
        #expect(caps.thinkingControl == .none)
        #expect(caps.authHeaderStyle == .bearer)
    }

    @Test func generationProfilePicksProviderActionDefaults() {
        let qwen = LLMGenerationProfile.resolve(providerId: "qwen", baseURLHost: "dashscope.aliyuncs.com", action: .rewrite)
        #expect(qwen.temperature == 0.2)
        #expect(qwen.topP == 0.8)
        #expect(qwen.timeout == 60)
        #expect(qwen.thinkingDefault == false)

        let mimo = LLMGenerationProfile.resolve(providerId: "mimo", baseURLHost: "api.xiaomimimo.com", action: .rewrite)
        #expect(mimo.temperature == 1.0)
        #expect(mimo.topP == 0.95)
        #expect(mimo.maxCompletionTokens == 1024)
    }
}
