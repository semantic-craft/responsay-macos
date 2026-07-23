import Foundation
import Testing
@testable import ResponsayCore

/// #566 — the cloud / local / no-key route is derived purely from the resolved endpoint.
struct IntentCompilerRouteTests {
    @Test func classify_cloudEndpointWithKey() {
        let cloud = LLMEndpoint(
            providerId: "qwen",
            baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
            model: "qwen-flash", apiKey: "sk-xxx")
        #expect(IntentCompilerRoute.classify(cloud) == .cloud(provider: "qwen"))
        #expect(IntentCompilerRoute.classify(cloud).isLocal == false)
        #expect(IntentCompilerRoute.classify(cloud).displayLabel == "云端 · qwen")
    }

    @Test func classify_localhostRunnerNeedsNoKey() {
        let ollama = LLMEndpoint(
            providerId: "ollama", baseURL: "http://localhost:11434/v1",
            model: "qwen2.5", apiKey: nil)
        let customLocal = LLMEndpoint(
            providerId: "custom", baseURL: "http://127.0.0.1:1234/v1",
            model: "local-model", apiKey: nil)

        #expect(IntentCompilerRoute.classify(ollama) == .local(provider: "ollama"))
        #expect(IntentCompilerRoute.classify(ollama).isLocal)
        #expect(IntentCompilerRoute.classify(ollama).displayLabel == "本机 · ollama")
        // A custom OpenAI-compatible endpoint pointed at loopback is local too (host match).
        #expect(IntentCompilerRoute.classify(customLocal) == .local(provider: "custom"))
    }

    @Test func classify_unavailableWhenNilOrUnconfigured() {
        #expect(IntentCompilerRoute.classify(nil) == .unavailable)
        // Cloud provider with no key → not configured → unavailable (无 Key 三态之一).
        let noKey = LLMEndpoint(
            providerId: "qwen", baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
            model: "qwen-flash", apiKey: nil)
        #expect(IntentCompilerRoute.classify(noKey) == .unavailable)
        // Missing model → unavailable even for a local host.
        let noModel = LLMEndpoint(
            providerId: "ollama", baseURL: "http://localhost:11434/v1", model: "", apiKey: nil)
        #expect(IntentCompilerRoute.classify(noModel) == .unavailable)
        #expect(IntentCompilerRoute.classify(nil).displayLabel == "未配置模型")
    }
}
