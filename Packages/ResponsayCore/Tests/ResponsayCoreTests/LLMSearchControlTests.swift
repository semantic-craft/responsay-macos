import Testing
import Foundation
@testable import ResponsayCore

// MARK: - LLMSearchControl tests

@Suite("LLMSearchControl — per-provider web-search params")
struct LLMSearchControlTests {

    // MARK: - supportsSearch

    @Test func qwen_supportsSearch() {
        #expect(LLMSearchControl.supportsSearch(providerId: "qwen", baseURLHost: "dashscope.aliyuncs.com"))
    }

    @Test func qwenTokenPlan_supportsSearch() {
        #expect(LLMSearchControl.supportsSearch(
            providerId: "qwen-token-plan",
            baseURLHost: "token-plan.cn-beijing.maas.aliyuncs.com"))
    }

    @Test func zhipu_supportsSearch() {
        #expect(LLMSearchControl.supportsSearch(providerId: "zhipu", baseURLHost: "open.bigmodel.cn"))
    }

    @Test func mimo_supportsSearch() {
        #expect(LLMSearchControl.supportsSearch(providerId: "mimo", baseURLHost: "api.xiaomimimo.com"))
        #expect(LLMSearchControl.supportsSearch(providerId: "mimo", baseURLHost: "token-plan-cn.xiaomimimo.com"))
    }

    @Test func deepseek_doesNotSupportSearch() {
        #expect(!LLMSearchControl.supportsSearch(providerId: "deepseek", baseURLHost: "api.deepseek.com"))
    }

    @Test func openai_doesNotSupportSearch() {
        #expect(!LLMSearchControl.supportsSearch(providerId: "openai", baseURLHost: "api.openai.com"))
    }

    @Test func ollama_doesNotSupportSearch() {
        #expect(!LLMSearchControl.supportsSearch(providerId: "ollama", baseURLHost: "localhost"))
    }

    @Test func custom_dashscopeHost_supportsSearch() {
        #expect(LLMSearchControl.supportsSearch(providerId: "custom", baseURLHost: "dashscope.aliyuncs.com"))
    }

    @Test func custom_unknownHost_doesNotSupportSearch() {
        #expect(!LLMSearchControl.supportsSearch(providerId: "custom", baseURLHost: "my-proxy.example.com"))
    }

    @Test func qwen_dashScopeHost_supportsSourceResults() {
        #expect(LLMSearchControl.supportsSourceResults(providerId: "qwen", baseURLHost: "dashscope.aliyuncs.com"))
    }

    @Test func qwenTokenPlan_nonDashScopeHost_doesNotSupportSourceResults() {
        #expect(!LLMSearchControl.supportsSourceResults(
            providerId: "qwen-token-plan",
            baseURLHost: "token-plan.cn-beijing.maas.aliyuncs.com"))
    }

    @Test func mimo_zhipu_supportSourceResults() {
        #expect(LLMSearchControl.supportsSourceResults(providerId: "mimo", baseURLHost: "api.xiaomimimo.com"))
        #expect(LLMSearchControl.supportsSourceResults(providerId: "mimo", baseURLHost: "token-plan-cn.xiaomimimo.com"))
        #expect(LLMSearchControl.supportsSourceResults(providerId: "zhipu", baseURLHost: "open.bigmodel.cn"))
    }

    // MARK: - searchEnabled: false → always empty

    @Test func searchDisabled_returnsEmpty_forAllProviders() {
        let providers = ["qwen", "zhipu", "mimo", "deepseek", "openai", "ollama"]
        for id in providers {
            let params = LLMSearchControl.extraBody(providerId: id, baseURLHost: "", searchEnabled: false)
            #expect(params.isEmpty, "Expected empty for \(id) when search disabled")
        }
    }

    // MARK: - Qwen (DashScope): enable_search: true

    @Test func qwen_searchEnabled_returnsEnableSearch() {
        let params = LLMSearchControl.extraBody(providerId: "qwen", baseURLHost: "dashscope.aliyuncs.com", searchEnabled: true)
        #expect(params["enable_search"] as? Bool == true)
        #expect(params["tools"] == nil)
    }

    @Test func qwenTokenPlan_searchEnabled_returnsEnableSearch() {
        let params = LLMSearchControl.extraBody(providerId: "qwen-token-plan", baseURLHost: "", searchEnabled: true)
        #expect(params["enable_search"] as? Bool == true)
    }

    // MARK: - Zhipu: tools with web_search type

    @Test func zhipu_searchEnabled_returnsWebSearchTool() throws {
        let params = LLMSearchControl.extraBody(providerId: "zhipu", baseURLHost: "open.bigmodel.cn", searchEnabled: true)
        let tools = try #require(params["tools"] as? [[String: Any]])
        #expect(tools.count == 1)
        let tool = tools[0]
        #expect(tool["type"] as? String == "web_search")
        let config = try #require(tool["web_search"] as? [String: Any])
        #expect(config["enable"] as? Bool == true)
        #expect(config["search_engine"] as? String == "search_pro")
        #expect(config["search_result"] as? Bool == true)
        #expect(params["tool_choice"] as? String == "auto")
    }

    // MARK: - MiMo: web_search tool

    @Test func mimo_searchEnabled_returnsWebSearchTool() throws {
        let params = LLMSearchControl.extraBody(providerId: "mimo", baseURLHost: "token-plan-cn.xiaomimimo.com", searchEnabled: true)
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

    @Test func deepseek_searchEnabled_returnsEmpty() {
        let params = LLMSearchControl.extraBody(providerId: "deepseek", baseURLHost: "api.deepseek.com", searchEnabled: true)
        #expect(params.isEmpty)
    }

    @Test func openai_searchEnabled_returnsEmpty() {
        let params = LLMSearchControl.extraBody(providerId: "openai", baseURLHost: "api.openai.com", searchEnabled: true)
        #expect(params.isEmpty)
    }

    @Test func ollama_searchEnabled_returnsEmpty() {
        let params = LLMSearchControl.extraBody(providerId: "ollama", baseURLHost: "localhost", searchEnabled: true)
        #expect(params.isEmpty)
    }

    @Test func gemini_searchEnabled_returnsEmpty() {
        let params = LLMSearchControl.extraBody(providerId: "gemini", baseURLHost: "generativelanguage.googleapis.com", searchEnabled: true)
        #expect(params.isEmpty)
    }

    @Test func minimax_searchEnabled_returnsEmpty() {
        let params = LLMSearchControl.extraBody(providerId: "minimax", baseURLHost: "api.minimaxi.com", searchEnabled: true)
        #expect(params.isEmpty)
    }

    @Test func unknownProvider_searchEnabled_returnsEmpty() {
        let params = LLMSearchControl.extraBody(providerId: "unknown", baseURLHost: "unknown.example.com", searchEnabled: true)
        #expect(params.isEmpty)
    }

    // MARK: - Host-based fallback for custom endpoints

    @Test func custom_bigmodelHost_resolvesToZhipu() throws {
        let params = LLMSearchControl.extraBody(providerId: "custom", baseURLHost: "open.bigmodel.cn", searchEnabled: true)
        let tools = try #require(params["tools"] as? [[String: Any]])
        #expect(tools[0]["type"] as? String == "web_search")
    }

    @Test func custom_xiaomimimoHost_resolvesToMiMo() throws {
        let params = LLMSearchControl.extraBody(providerId: "custom", baseURLHost: "api.xiaomimimo.com", searchEnabled: true)
        let tools = try #require(params["tools"] as? [[String: Any]])
        #expect(tools[0]["type"] as? String == "web_search")
    }
}
