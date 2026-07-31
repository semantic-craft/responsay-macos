import Foundation
import Testing
@testable import ResponsayCore

struct LLMProviderCapabilitiesTests {
    @Test func qwenCapabilitiesPreferResponsesWithOfficialToolsAndReasoningControl() {
        let caps = LLMProviderCapabilities.resolve(providerId: "qwen", baseURLHost: "dashscope.aliyuncs.com")

        #expect(caps.supportsChatCompletions)
        #expect(caps.supportsResponses)
        #expect(!caps.supportsStreamUsage)
        #expect(caps.supportsBatch)
        #expect(caps.builtinTools.contains(.webSearch))
        #expect(caps.authHeaderStyle == .bearer)
        #expect(caps.thinkingControl == .reasoningEffort)
        #expect(LLMProviderCapabilities.prefersResponses(
            providerId: "qwen",
            model: "qwen-plus",
            baseURLHost: "dashscope.aliyuncs.com"))
    }

    /// DeepSeek 只把 `deepseek-v4-flash` 迁到了 Responses；v4-pro 官方称 2026 年 8 月初才支持，
    /// 在那之前把它一起切过去会让自定义卡片直接打不通，所以按模型分流。
    @Test func deepSeekPrefersResponsesOnlyForV4Flash() {
        let caps = LLMProviderCapabilities.resolve(providerId: "deepseek", baseURLHost: "api.deepseek.com")
        #expect(caps.supportsChatCompletions)
        #expect(caps.supportsResponses)
        #expect(caps.supportsThinkingControl)
        #expect(caps.authHeaderStyle == .bearer)

        #expect(LLMProviderCapabilities.prefersResponses(
            providerId: "deepseek", model: "deepseek-v4-flash", baseURLHost: "api.deepseek.com"))
        #expect(!LLMProviderCapabilities.prefersResponses(
            providerId: "deepseek", model: "deepseek-v4-pro", baseURLHost: "api.deepseek.com"))
        #expect(!LLMProviderCapabilities.prefersResponses(
            providerId: "deepseek", model: "deepseek-chat", baseURLHost: "api.deepseek.com"))
        // 自定义卡片指到 DeepSeek 时按 host 归并到同一通道。
        #expect(LLMProviderCapabilities.prefersResponses(
            providerId: "custom", model: "deepseek-v4-flash", baseURLHost: "api.deepseek.com"))
        // 其他 provider 不因为模型名沾边就改道。
        #expect(!LLMProviderCapabilities.prefersResponses(
            providerId: "openrouter", model: "deepseek-v4-flash", baseURLHost: "openrouter.ai"))
    }

    @Test func mimoCapabilitiesUseApiKeyAuthAndDisableResponsesOnlyFeatures() {
        let caps = LLMProviderCapabilities.resolve(providerId: "mimo", baseURLHost: "api.xiaomimimo.com")

        #expect(caps.supportsChatCompletions)
        #expect(caps.authHeaderStyle == .apiKeyHeader("api-key"))
        #expect(caps.thinkingControl == .thinkingObject)
        #expect(!caps.supportsResponses)
        #expect(caps.builtinTools.contains(.webSearch))
    }

    @Test func geminiCapabilitiesExposeItsThinkingControl() {
        // 智谱已退役：其 host 不再解析为专属通道，落到未知 provider 的保守能力集。
        let retired = LLMProviderCapabilities.resolve(providerId: "zhipu", baseURLHost: "open.bigmodel.cn")
        #expect(!retired.supportsResponses)

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
        #expect(qwen.topP == nil)
        #expect(qwen.timeout == 60)
        #expect(qwen.thinkingDefault == false)

        let mimo = LLMGenerationProfile.resolve(providerId: "mimo", baseURLHost: "api.xiaomimimo.com", action: .rewrite)
        #expect(mimo.temperature == 1.0)
        #expect(mimo.topP == 0.95)
        #expect(mimo.maxCompletionTokens == 1024)
    }
}
