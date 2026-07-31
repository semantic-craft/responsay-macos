import Testing
import Foundation
@testable import ResponsayCore

// MARK: - LLMSearchControl tests

@Suite("LLMSearchControl — per-provider web-search params")
struct LLMSearchControlTests {

    // MARK: - supportsSearch

    @Test func qwen_supportsSearch() {
        #expect(LLMSearchControl.supportsSearch(providerId: "qwen", model: "qwen-plus", baseURLHost: "dashscope.aliyuncs.com"))
    }

    @Test func retiredZhipu_doesNotSupportSearch() {
        #expect(!LLMSearchControl.supportsSearch(providerId: "zhipu", model: "glm-4", baseURLHost: "open.bigmodel.cn"))
    }

    @Test func mimo_supportsSearch() {
        #expect(LLMSearchControl.supportsSearch(providerId: "mimo", model: "mimo-v2.5", baseURLHost: "api.xiaomimimo.com"))
        #expect(LLMSearchControl.supportsSearch(providerId: "mimo", model: "mimo-v2.5", baseURLHost: "token-plan-cn.xiaomimimo.com"))
    }

    /// DeepSeek 的 web_search 是 Responses 上的服务端工具，所以联网能力跟着路由按模型收窄：
    /// 只有走 Responses 的 v4-flash 能搜，其余模型仍在 /chat/completions 上、发工具会 400。
    @Test func deepseek_supportsSearchOnlyOnResponsesModel() {
        #expect(LLMSearchControl.supportsSearch(
            providerId: "deepseek", model: "deepseek-v4-flash", baseURLHost: "api.deepseek.com"))
        #expect(!LLMSearchControl.supportsSearch(
            providerId: "deepseek", model: "deepseek-v4-pro", baseURLHost: "api.deepseek.com"))
        #expect(!LLMSearchControl.supportsSearch(
            providerId: "deepseek", model: "deepseek-chat", baseURLHost: "api.deepseek.com"))
        // 自定义卡片指到 DeepSeek 也一样按 host + 模型归并。
        #expect(LLMSearchControl.supportsSearch(
            providerId: "custom", model: "deepseek-v4-flash", baseURLHost: "api.deepseek.com"))
    }

    @Test func deepseek_supportsSourceResultsOnlyOnResponsesModel() {
        #expect(LLMSearchControl.supportsSourceResults(
            providerId: "deepseek", model: "deepseek-v4-flash", baseURLHost: "api.deepseek.com"))
        #expect(!LLMSearchControl.supportsSourceResults(
            providerId: "deepseek", model: "deepseek-chat", baseURLHost: "api.deepseek.com"))
    }

    @Test func openai_doesNotSupportSearch() {
        #expect(!LLMSearchControl.supportsSearch(providerId: "openai", model: "gpt-4.1", baseURLHost: "api.openai.com"))
    }

    @Test func ollama_doesNotSupportSearch() {
        #expect(!LLMSearchControl.supportsSearch(providerId: "ollama", model: "gemma4:e4b", baseURLHost: "localhost"))
    }

    @Test func custom_dashscopeHost_supportsSearch() {
        #expect(LLMSearchControl.supportsSearch(providerId: "custom", model: "x", baseURLHost: "dashscope.aliyuncs.com"))
    }

    @Test func custom_unknownHost_doesNotSupportSearch() {
        #expect(!LLMSearchControl.supportsSearch(providerId: "custom", model: "x", baseURLHost: "my-proxy.example.com"))
    }

    @Test func qwen_dashScopeHost_supportsSourceResults() {
        #expect(LLMSearchControl.supportsSourceResults(providerId: "qwen", model: "qwen-plus", baseURLHost: "dashscope.aliyuncs.com"))
    }

    @Test func mimo_supportsSourceResults() {
        #expect(LLMSearchControl.supportsSourceResults(providerId: "mimo", model: "mimo-v2.5", baseURLHost: "api.xiaomimimo.com"))
        #expect(LLMSearchControl.supportsSourceResults(providerId: "mimo", model: "mimo-v2.5", baseURLHost: "token-plan-cn.xiaomimimo.com"))
    }

    // MARK: - searchEnabled: false → always empty

    @Test func searchDisabled_returnsEmpty_forAllProviders() {
        let providers = ["qwen", "mimo", "deepseek", "openai", "ollama"]
        for id in providers {
            let params = LLMSearchControl.extraBody(providerId: id, model: "m", baseURLHost: "", searchEnabled: false)
            #expect(params.isEmpty, "Expected empty for \(id) when search disabled")
        }
    }

    // MARK: - Qwen Responses: official web_search tool

    @Test func qwen_searchEnabled_returnsResponsesWebSearchTool() throws {
        let params = LLMSearchControl.extraBody(providerId: "qwen", model: "qwen-plus", baseURLHost: "dashscope.aliyuncs.com", searchEnabled: true)
        let tools = try #require(params["tools"] as? [[String: Any]])
        #expect(tools.count == 1)
        #expect(tools.first?["type"] as? String == "web_search")
        // `auto`, never `required`: Bailian's server-side tool loop applies tool_choice to
        // every internal turn, so `required` forbids the final text turn — the model repeats
        // searches until the server rejects with "Repetitive tool calls detected" HTTP 400
        // (类案检索 0/3, live eval 2026-07-31).
        #expect(params["tool_choice"] as? String == "auto")
        // Server-side loop cap: flash still repeats identical searches under `auto`; the cap
        // forces the loop into the final text turn (mirrors Ark's production max_tool_calls).
        #expect(params["max_tool_calls"] as? Int == 3)
        #expect(params["enable_search"] == nil)
    }

    // MARK: - MiMo: web_search tool

    @Test func mimo_searchEnabled_returnsWebSearchTool() throws {
        let params = LLMSearchControl.extraBody(providerId: "mimo", model: "mimo-v2.5", baseURLHost: "token-plan-cn.xiaomimimo.com", searchEnabled: true)
        let tools = try #require(params["tools"] as? [[String: Any]])
        #expect(tools.count == 1)
        let tool = tools[0]
        #expect(tool["type"] as? String == "web_search")
        #expect(tool["max_keyword"] as? Int == 3)
        #expect(tool["force_search"] as? Bool == true)
        #expect(tool["limit"] as? Int == 1)
        #expect(params["tool_choice"] as? String == "auto")
        let thinking = try #require(params["thinking"] as? [String: Any])
        #expect(thinking["type"] as? String == "disabled")
    }

    // MARK: - No-op providers

    // MARK: - DeepSeek Responses: server-side web_search tool

    @Test func deepseek_v4Flash_searchEnabled_returnsResponsesWebSearchTool() throws {
        let params = LLMSearchControl.extraBody(
            providerId: "deepseek", model: "deepseek-v4-flash",
            baseURLHost: "api.deepseek.com", searchEnabled: true)
        let tools = try #require(params["tools"] as? [[String: Any]])
        #expect(tools.count == 1)
        #expect(tools.first?["type"] as? String == "web_search")
        #expect(params["tool_choice"] as? String == "auto")
        // 官方明说 max_tool_calls 被忽略 —— 不发，免得看起来像在封顶（百炼那边它是真生效的）。
        #expect(params["max_tool_calls"] == nil)
        #expect(params["enable_search"] == nil)
    }

    /// 非 Responses 的 DeepSeek 模型一个搜索字段都不能发：它们仍在 /chat/completions 上，
    /// 收到 `tools:[{type:web_search}]` 会当成缺 function 定义的工具而 400。
    @Test func deepseek_nonResponsesModels_searchEnabled_returnsEmpty() {
        for model in ["deepseek-v4-pro", "deepseek-chat"] {
            let params = LLMSearchControl.extraBody(
                providerId: "deepseek", model: model,
                baseURLHost: "api.deepseek.com", searchEnabled: true)
            #expect(params.isEmpty, "Expected no search params for \(model)")
        }
    }

    @Test func openai_searchEnabled_returnsEmpty() {
        let params = LLMSearchControl.extraBody(providerId: "openai", model: "gpt-4.1", baseURLHost: "api.openai.com", searchEnabled: true)
        #expect(params.isEmpty)
    }

    @Test func ollama_searchEnabled_returnsEmpty() {
        let params = LLMSearchControl.extraBody(providerId: "ollama", model: "gemma4:e4b", baseURLHost: "localhost", searchEnabled: true)
        #expect(params.isEmpty)
    }

    @Test func gemini_searchEnabled_returnsEmpty() {
        let params = LLMSearchControl.extraBody(providerId: "gemini", model: "gemini-2.5-flash", baseURLHost: "generativelanguage.googleapis.com", searchEnabled: true)
        #expect(params.isEmpty)
    }

    @Test func minimax_searchEnabled_returnsEmpty() {
        let params = LLMSearchControl.extraBody(providerId: "minimax", model: "MiniMax-M3", baseURLHost: "api.minimaxi.com", searchEnabled: true)
        #expect(params.isEmpty)
    }

    @Test func unknownProvider_searchEnabled_returnsEmpty() {
        let params = LLMSearchControl.extraBody(providerId: "unknown", model: "x", baseURLHost: "unknown.example.com", searchEnabled: true)
        #expect(params.isEmpty)
    }

    // MARK: - Host-based fallback for custom endpoints

    @Test func customBigmodelHostDoesNotEnableRetiredVendorSearch() {
        // 智谱退役后，指向其域名的自定义端点不再获得联网能力（豆包 ASR 的 bigmodel_nostream
        // 是同名不同物，走 ASR 路径，不受影响）。
        let params = LLMSearchControl.extraBody(providerId: "custom", model: "x", baseURLHost: "open.bigmodel.cn", searchEnabled: true)
        #expect(params.isEmpty)
        #expect(!LLMSearchControl.supportsSearch(providerId: "custom", model: "x", baseURLHost: "open.bigmodel.cn"))
    }

    @Test func custom_xiaomimimoHost_resolvesToMiMo() throws {
        let params = LLMSearchControl.extraBody(providerId: "custom", model: "x", baseURLHost: "api.xiaomimimo.com", searchEnabled: true)
        let tools = try #require(params["tools"] as? [[String: Any]])
        #expect(tools[0]["type"] as? String == "web_search")
    }
}
