import Testing
import Foundation
@testable import ResponsayCore

// Dedicated stub with its own static state so the LLM suite can't race other suites that
// install a URLProtocol stub over shared mutable state.
final class LLMStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var data = Data()
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var requestBody = Data()
    nonisolated(unsafe) static var requestURL: URL?
    nonisolated(unsafe) static var requestHeaders: [String: String] = [:]
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requestBody = request.httpBody ?? Self.readBodyStream(request.httpBodyStream)
        Self.requestURL = request.url
        Self.requestHeaders = request.allHTTPHeaderFields ?? [:]
        let resp = HTTPURLResponse(url: request.url!, statusCode: Self.status,
                                   httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    static func readBodyStream(_ stream: InputStream?) -> Data {
        guard let stream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private func llmStubSession() -> URLSession {
    let cfg = URLSessionConfiguration.ephemeral
    cfg.protocolClasses = [LLMStubURLProtocol.self]
    return URLSession(configuration: cfg)
}

/// Wrap a model JSON envelope into an OpenAI Responses response body.
private func responsesCompletion(content: String) -> Data {
    let obj: [String: Any] = [
        "object": "response",
        "status": "completed",
        "output": [[
            "type": "message",
            "role": "assistant",
            "content": [["type": "output_text", "text": content]],
        ]],
    ]
    return try! JSONSerialization.data(withJSONObject: obj)
}

// MARK: - Prompt port

struct RewritePromptBuilderTests {
    @Test func rewrite_user_carriesTextAndAsksSameLanguage() {
        let p = RewritePromptBuilder.build(text: "这个 缓存 要改一下", tone: .natural)
        #expect(p.user.contains("这个 缓存 要改一下"))
        #expect(p.system.contains("THE SAME source language/locale"))
        #expect(p.system.contains("{\"text\": string, \"changes\": string[]}"))
    }

    @Test func rewrite_eachToneHasDistinctDirective() {
        let tones: [RewriteTone] = [.natural, .casual, .formal, .structured, .concise]
        let directives = Set(tones.map { RewritePromptBuilder.toneDirective($0) })
        #expect(directives.count == tones.count)            // all distinct
        #expect(RewritePromptBuilder.toneDirective(.concise).contains("更简短"))
        #expect(RewritePromptBuilder.toneDirective(.structured).contains("结构化"))
    }
}

// MARK: - 思考 fan-out

struct LLMThinkingControlTests {
    private func body(_ pid: String, _ model: String, _ on: Bool, host: String = "", streaming: Bool = false) -> [String: Any] {
        LLMThinkingControl.extraBody(providerId: pid, model: model, baseURLHost: host, enabled: on, streaming: streaming)
    }

    @Test func openai_reasoningModel_emitsEffort_plainChatEmitsNothing() {
        #expect(body("openai", "gpt-5.5", true)["reasoning_effort"] as? String == "medium")
        #expect(body("openai", "o3", false)["reasoning_effort"] as? String == "low")
        #expect(body("openai", "gpt-4.1", true).isEmpty)   // plain chat → nothing (would 400)
        #expect(body("openai", "o2", true).isEmpty)        // o2/o5… aren't real reasoning families
        #expect(body("openai", "gpt-5-pro", false)["reasoning_effort"] as? String == "high")   // pro forced high
        #expect(body("openai", "openai/gpt-5-mini", true)["reasoning_effort"] as? String == "medium")  // slug prefix stripped
    }

    @Test func dashScopeResponses_usesReasoningEffortForBothModes() {
        #expect((body("qwen", "qwen-plus", true)["reasoning"] as? [String: String])?["effort"] == "medium")
        #expect((body("qwen", "qwen-plus", false)["reasoning"] as? [String: String])?["effort"] == "none")
        #expect((body("qwen", "qwen-plus", true, streaming: true)["reasoning"] as? [String: String])?["effort"] == "medium")
        #expect((body("qwen", "qwen-plus", false, streaming: true)["reasoning"] as? [String: String])?["effort"] == "none")
    }

    @Test func openrouter_reasoningWithExclude() {
        let on = body("custom", "anthropic/claude", true, host: "openrouter.ai")["reasoning"] as? [String: Any]
        #expect(on?["effort"] as? String == "medium")
        #expect(on?["exclude"] as? Bool == true)
        #expect((body("custom", "x", false, host: "openrouter.ai")["reasoning"] as? [String: Any])?["effort"] as? String == "none")
    }

    @Test func deepseek_mimo_doubao_thinkingType() {
        #expect((body("deepseek", "deepseek-chat", true)["thinking"] as? [String: String])?["type"] == "enabled")
        #expect((body("mimo", "mimo-v2.5-pro", false)["thinking"] as? [String: String])?["type"] == "disabled")
        #expect((body("doubao", "doubao-seed-2-0-lite-260428", false, host: "ark.cn-beijing.volces.com")["thinking"] as? [String: String])?["type"] == "disabled")
    }

    // 423 — MiniMax OpenAI-compat /v1: M3's interleaved thinking is injected as <think>…</think>
    // INTO `content` by default, which corrupts our structured-JSON replies. `reasoning_split:true`
    // relocates the trace to a separate `reasoning_details` field so `content` stays clean JSON.
    // (`thinking:{type:…}` is the Anthropic-endpoint param, not understood on /v1.) Always split —
    // the app never surfaces the trace, and M2.7-highspeed has little to split.
    @Test func minimax_reasoningSplit_keepsContentCleanJSON() {
        #expect(body("minimax", "MiniMax-M3", false)["reasoning_split"] as? Bool == true)
        #expect(body("minimax", "MiniMax-M2.7-highspeed", true)["reasoning_split"] as? Bool == true)
        #expect(body("minimax", "MiniMax-M3", false)["thinking"] == nil)
        // a custom endpoint pointed at MiniMax routes by host
        #expect(body("custom", "MiniMax-M3", false, host: "api.minimaxi.com")["reasoning_split"] as? Bool == true)
    }

    @Test func gemini_sendsNoneOnlyForOlderNonProFamilies_omitsRestWhenOff() {
        // Older non-pro 2.x/1.x flash-class ids accept `reasoning_effort:"none"` to disable thinking.
        #expect(body("gemini", "gemini-2.5-flash", false)["reasoning_effort"] as? String == "none")
        #expect(body("gemini", "gemini-2.5-flash", true)["reasoning_effort"] as? String == "medium")
        // Pro can't fully disable thinking — emit nothing rather than an ineffective/invalid "none".
        #expect(body("gemini", "gemini-2.5-pro", false).isEmpty)
        #expect(body("gemini", "gemini-2.5-pro", true)["reasoning_effort"] as? String == "medium")
        // 3.5 generation HTTP-400s on "none" → omit when off (it isn't a 2.x/1.x id), despite "flash-lite".
        #expect(body("gemini", "gemini-3.5-flash-lite", false).isEmpty)
        #expect(body("gemini", "gemini-3.5-flash-lite", true)["reasoning_effort"] as? String == "medium")
        // Regression (1.5.4): `*-latest` aliases resolve to the 3.5 generation and 400 on "none",
        // yet contain no "gemini-3" — the old substring guard wrongly sent "none". Now they OMIT.
        #expect(body("gemini", "gemini-flash-latest", false).isEmpty)
        #expect(body("gemini", "gemini-flash-latest", true)["reasoning_effort"] as? String == "medium")
        #expect(body("gemini", "gemini-flash-lite-latest", false).isEmpty)
    }

    @Test func ollama_disablesViaNone() {
        #expect(body("ollama", "gemma4:e4b", false)["reasoning_effort"] as? String == "none")
        #expect(body("ollama", "gemma4:e4b", true).isEmpty)
    }

    @Test func custom_routesByHost() {
        #expect((body("custom", "qwen-plus", false, host: "dashscope.aliyuncs.com")["reasoning"] as? [String: String])?["effort"] == "none")
        #expect(body("custom", "x", true, host: "generativelanguage.googleapis.com")["reasoning_effort"] as? String == "medium")
        #expect((body("custom", "doubao-seed", false, host: "ark.cn-beijing.volces.com")["thinking"] as? [String: String])?["type"] == "disabled")
        // 智谱退役后其域名不再有专属通道 → 与未知 host 一样什么都不发（发明字段会 400）。
        #expect(body("custom", "glm-5-turbo", false, host: "open.bigmodel.cn").isEmpty)
        #expect(body("custom", "x", true, host: "unknown.example.com").isEmpty)   // unknown → emit nothing
    }

    /// Providers with no documented 思考 parameter (Kimi, unknown 自定义 hosts) emit nothing —
    /// the model choice decides, and an invented field would 400.
    @Test func channellessProviders_emitNothing() {
        #expect(body("kimi", "kimi-k2", false, host: "api.moonshot.cn").isEmpty)
        #expect(body("unknown", "x", false, host: "unknown.example.com").isEmpty)
    }
}

// MARK: - Wire helpers

struct LLMWireTests {
    @Test func chatCompletionsURL_normalizes() {
        #expect(LLMWire.chatCompletionsURL(base: "https://dashscope.aliyuncs.com/compatible-mode/v1")?.absoluteString
                == "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")
        // Gemini openai-compat has a trailing slash.
        #expect(LLMWire.chatCompletionsURL(base: "https://generativelanguage.googleapis.com/v1beta/openai/")?.absoluteString
                == "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")
        // Already-complete URL is reused.
        #expect(LLMWire.chatCompletionsURL(base: "https://x.com/v1/chat/completions")?.absoluteString
                == "https://x.com/v1/chat/completions")
        #expect(LLMWire.chatCompletionsURL(base: "   ") == nil)
    }

    @Test func modelsURL_normalizes() {
        #expect(LLMWire.modelsURL(base: "https://api.openai.com/v1")?.absoluteString == "https://api.openai.com/v1/models")
        #expect(LLMWire.modelsURL(base: "https://x.com/v1/chat/completions")?.absoluteString == "https://x.com/v1/models")
        #expect(LLMWire.modelsURL(base: "https://x.com/v1/models")?.absoluteString == "https://x.com/v1/models")
    }

    @Test func authHeaders_bearerExceptMimoApiKey() {
        #expect(LLMWire.authHeaders(providerId: "openai", key: "sk-1")["Authorization"] == "Bearer sk-1")
        #expect(LLMWire.authHeaders(providerId: "doubao", key: "ark-test")["Authorization"] == "Bearer ark-test")
        #expect(LLMWire.authHeaders(providerId: "mimo", key: "tp-1")["api-key"] == "tp-1")
        #expect(LLMWire.authHeaders(providerId: "mimo", key: "tp-1")["Authorization"] == nil)
        #expect(LLMWire.authHeaders(providerId: "openai", key: nil).isEmpty)
    }
}

// MARK: - Request builder

struct LLMChatRequestBuilderTests {
    private func endpoint(thinking: Bool = false) -> LLMEndpoint {
        LLMEndpoint(providerId: "qwen", baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
                    model: "qwen-plus", apiKey: "sk-1", thinkingEnabled: thinking)
    }

    @Test func buildsQwenResponsesShapeBody() throws {
        let req = try LLMChatRequestBuilder.makeRequest(endpoint: endpoint(), system: "SYS", user: "USR")
        #expect(req.url?.absoluteString == "https://dashscope.aliyuncs.com/compatible-mode/v1/responses")
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer sk-1")
        let body = try JSONSerialization.jsonObject(with: req.httpBody!) as? [String: Any]
        #expect(body?["model"] as? String == "qwen-plus")
        #expect(body?["stream"] as? Bool == false)
        #expect(body?["store"] as? Bool == false)
        let input = body?["input"] as? [[String: String]]
        #expect(input?.first?["role"] == "system")
        #expect(input?.first?["content"] == "SYS")
        #expect(input?.last?["content"] == "USR")
        #expect((body?["reasoning"] as? [String: String])?["effort"] == "none")
        #expect(body?["messages"] == nil)
        #expect(body?["enable_thinking"] == nil)
    }

    // 听写(flash)与技能平台(max)分流后，两条 lane 的请求必须同样命中 /responses、
    // store=false、reasoning.effort=none —— 只有 model 字段不同。
    @Test func bothWorkflowModels_hitResponses_storeFalse_reasoningNone() throws {
        for model in ["qwen3.7-flash", "qwen3.7-max"] {
            let ep = LLMEndpoint(
                providerId: "qwen", baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
                model: model, apiKey: "sk-1", thinkingEnabled: false)
            let req = try LLMChatRequestBuilder.makeRequest(endpoint: ep, system: "SYS", user: "USR")
            #expect(req.url?.path == "/compatible-mode/v1/responses")
            let body = try JSONSerialization.jsonObject(with: req.httpBody!) as? [String: Any]
            #expect(body?["model"] as? String == model)
            #expect(body?["store"] as? Bool == false)
            #expect((body?["reasoning"] as? [String: String])?["effort"] == "none")
            #expect(body?["messages"] == nil)
        }
    }

    @Test func ordinaryQwenResponsesRequestOmitsToolsAndLegacyChatFields() throws {
        let req = try LLMChatRequestBuilder.makeRequest(endpoint: endpoint(), system: "SYS", user: "USR")
        let body = try JSONSerialization.jsonObject(with: req.httpBody!) as? [String: Any]

        for field in ["tools", "tool_choice", "enable_search", "mcp", "messages", "instructions", "modalities", "stream_options"] {
            #expect(body?[field] == nil)
        }
        #expect(body?["input"] != nil)
        #expect(body?["reasoning"] != nil)
        #expect(body?["response_format"] == nil)
    }

    @Test func qwenRewriteAppliesLowLatencyGenerationProfile() throws {
        let req = try LLMChatRequestBuilder.makeRequest(endpoint: endpoint(), system: "SYS", user: "USR")
        let body = try JSONSerialization.jsonObject(with: req.httpBody!) as? [String: Any]

        #expect(body?["temperature"] as? Double == 0.2)
        // 百炼 Responses 文档建议 temperature / top_p 只设置一个。
        #expect(body?["top_p"] == nil)
    }

    @Test func doubaoRewriteUsesArkChatCompletionsAndDisablesThinking() throws {
        let endpoint = LLMEndpoint(
            providerId: "doubao",
            baseURL: "https://ark.cn-beijing.volces.com/api/v3",
            model: "doubao-seed-2-0-lite-260428",
            apiKey: "ark-test-key",
            thinkingEnabled: false)

        let req = try LLMChatRequestBuilder.makeRequest(endpoint: endpoint, system: "SYS", user: "USR")
        let body = try #require(JSONSerialization.jsonObject(with: req.httpBody!) as? [String: Any])

        #expect(req.url?.absoluteString == "https://ark.cn-beijing.volces.com/api/v3/chat/completions")
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer ark-test-key")
        #expect(body["model"] as? String == "doubao-seed-2-0-lite-260428")
        #expect(body["stream"] as? Bool == false)
        #expect(body["temperature"] as? Double == 0.2)
        #expect(body["top_p"] as? Double == 0.8)
        #expect((body["thinking"] as? [String: String])?["type"] == "disabled")
        for field in ["tools", "tool_choice", "enable_search", "mcp", "input", "instructions"] {
            #expect(body[field] == nil)
        }
    }

    @Test func doubaoSearchVerificationUsesArkResponsesWebSearchPlugin() throws {
        let endpoint = LLMEndpoint(
            providerId: "doubao",
            baseURL: "https://ark.cn-beijing.volces.com/api/v3",
            model: "doubao-seed-2-0-lite-260428",
            apiKey: "ark-test-key",
            thinkingEnabled: false)

        let req = try ArkResponsesSearchRequestBuilder.makeRequest(
            endpoint: endpoint,
            system: "SYS",
            user: "USR")
        let body = try #require(JSONSerialization.jsonObject(with: req.httpBody!) as? [String: Any])

        #expect(req.url?.absoluteString == "https://ark.cn-beijing.volces.com/api/v3/responses")
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer ark-test-key")
        #expect(body["model"] as? String == "doubao-seed-2-0-lite-260428")
        #expect(body["stream"] as? Bool == false)
        #expect((body["thinking"] as? [String: String])?["type"] == "disabled")
        #expect(body["max_tool_calls"] as? Int == 3)
        #expect(body["messages"] == nil)

        let input = try #require(body["input"] as? [[String: Any]])
        #expect(input.count == 2)
        #expect(input.first?["role"] as? String == "system")
        let content = try #require(input.last?["content"] as? [[String: Any]])
        #expect(content.first?["type"] as? String == "input_text")
        #expect(content.first?["text"] as? String == "USR")

        let tools = try #require(body["tools"] as? [[String: Any]])
        #expect(tools.first?["type"] as? String == "web_search")
        #expect(tools.first?["max_keyword"] as? Int == 2)
        #expect(tools.first?["limit"] as? Int == 3)
    }

    @Test func mimoRejectsKeyEndpointPlanMixups() throws {
        let tokenPlanWithPaygKey = LLMEndpoint(
            providerId: "mimo",
            baseURL: "https://token-plan-cn.xiaomimimo.com/v1",
            model: "mimo-v2.5",
            apiKey: "sk-payg")
        #expect(throws: LLMError.invalidConfiguration("MiMo Token Plan endpoints require a tp- key.")) {
            _ = try LLMChatRequestBuilder.makeRequest(
                endpoint: tokenPlanWithPaygKey,
                system: "SYS",
                user: "USR")
        }

        let paygWithTokenPlanKey = LLMEndpoint(
            providerId: "mimo",
            baseURL: "https://api.xiaomimimo.com/v1",
            model: "mimo-v2.5",
            apiKey: "tp-token-plan")
        #expect(throws: LLMError.invalidConfiguration("MiMo pay-as-you-go endpoints require an sk- key.")) {
            _ = try LLMChatRequestBuilder.makeRequest(
                endpoint: paygWithTokenPlanKey,
                system: "SYS",
                user: "USR")
        }
    }

    @Test func mimoV25RewriteAppliesOfficialProfileThinkingDisabledAndApiKeyHeader() throws {
        let endpoint = LLMEndpoint(
            providerId: "mimo",
            baseURL: "https://token-plan-cn.xiaomimimo.com/v1",
            model: "mimo-v2.5",
            apiKey: "tp-token-plan",
            thinkingEnabled: false)

        let req = try LLMChatRequestBuilder.makeRequest(endpoint: endpoint, system: "SYS", user: "USR")

        #expect(req.value(forHTTPHeaderField: "api-key") == "tp-token-plan")
        #expect(req.value(forHTTPHeaderField: "Authorization") == nil)
        let body = try JSONSerialization.jsonObject(with: req.httpBody!) as? [String: Any]
        #expect(body?["model"] as? String == "mimo-v2.5")
        #expect(body?["temperature"] as? Double == 1.0)
        #expect(body?["top_p"] as? Double == 0.95)
        #expect(body?["max_completion_tokens"] as? Int == 1024)
        #expect(body?["frequency_penalty"] as? Double == 0)
        #expect(body?["presence_penalty"] as? Double == 0)
        #expect((body?["thinking"] as? [String: String])?["type"] == "disabled")
    }

    @Test func mimoThinkingOnDoesNotUseLowLatencyRewriteTemperature() throws {
        let endpoint = LLMEndpoint(
            providerId: "mimo",
            baseURL: "https://api.xiaomimimo.com/v1",
            model: "mimo-v2.5",
            apiKey: "sk-payg",
            thinkingEnabled: true)

        let req = try LLMChatRequestBuilder.makeRequest(endpoint: endpoint, system: "SYS", user: "USR")
        let body = try JSONSerialization.jsonObject(with: req.httpBody!) as? [String: Any]
        #expect((body?["thinking"] as? [String: String])?["type"] == "enabled")
        #expect(body?["temperature"] as? Double == 1.0)
        #expect(body?["top_p"] as? Double == 0.95)
    }

    @Test func unknownCustomEndpointOmitsProviderSpecificGenerationAndThinkingFields() throws {
        let custom = LLMEndpoint(
            providerId: "custom",
            baseURL: "https://llm.example.test/v1",
            model: "custom-fast",
            apiKey: "sk-1")
        let req = try LLMChatRequestBuilder.makeRequest(endpoint: custom, system: "SYS", user: "USR")
        let body = try JSONSerialization.jsonObject(with: req.httpBody!) as? [String: Any]

        for field in ["temperature", "top_p", "max_completion_tokens", "enable_thinking", "thinking", "reasoning_effort", "reasoning"] {
            #expect(body?[field] == nil)
        }
    }

    @Test func thinkingOn_dashScopeResponses_usesReasoningEffort() throws {
        let req = try LLMChatRequestBuilder.makeRequest(endpoint: endpoint(thinking: true), system: "S", user: "U")
        let body = try JSONSerialization.jsonObject(with: req.httpBody!) as? [String: Any]
        #expect((body?["reasoning"] as? [String: String])?["effort"] == "medium")
        #expect(body?["enable_thinking"] == nil)
    }

    @Test func thinkingOn_openAIReasoning_ridesIntoBody() throws {
        let openai = LLMEndpoint(providerId: "openai", baseURL: "https://api.openai.com/v1",
                                 model: "gpt-5.5", apiKey: "sk-1", thinkingEnabled: true)
        let req = try LLMChatRequestBuilder.makeRequest(endpoint: openai, system: "S", user: "U")
        let body = try JSONSerialization.jsonObject(with: req.httpBody!) as? [String: Any]
        #expect(body?["reasoning_effort"] as? String == "medium")
    }

    @Test func notConfigured_throws() {
        let bad = LLMEndpoint(providerId: "openai", baseURL: "https://api.openai.com/v1", model: "gpt-5.5", apiKey: nil)
        #expect(throws: LLMError.self) {
            _ = try LLMChatRequestBuilder.makeRequest(endpoint: bad, system: "s", user: "u")
        }
    }

    @Test func responseFormat_localOnly_andColdLoadTimeout() throws {
        let local = LLMEndpoint(providerId: "ollama", baseURL: "http://localhost:11434/v1",
                                model: "gemma4:e4b", apiKey: nil)
        let lreq = try LLMChatRequestBuilder.makeRequest(
            endpoint: local, system: "s", user: "u", responseFormat: LLMResponseFormat.textChanges)
        let lbody = try JSONSerialization.jsonObject(with: lreq.httpBody!) as? [String: Any]
        #expect(lbody?["response_format"] != nil)             // local → json_schema sent
        #expect(lbody?["reasoning_effort"] as? String == "none")  // local thinking off
        #expect(lreq.timeoutInterval == 300)                  // cold-load budget

        // Cloud: response_format omitted even if passed (some providers 400 on it); 60s.
        let creq = try LLMChatRequestBuilder.makeRequest(
            endpoint: endpoint(), system: "s", user: "u", responseFormat: LLMResponseFormat.textChanges)
        let cbody = try JSONSerialization.jsonObject(with: creq.httpBody!) as? [String: Any]
        #expect(cbody?["response_format"] == nil)
        #expect(creq.timeoutInterval == 60)
    }

    @Test func searchEnabled_dashScopeResponsesAddsOfficialWebSearchTool() throws {
        let req = try LLMChatRequestBuilder.makeRequest(
            endpoint: endpoint(thinking: true),
            system: "s",
            user: "u",
            searchEnabled: true)
        let body = try JSONSerialization.jsonObject(with: req.httpBody!) as? [String: Any]
        let tools = try #require(body?["tools"] as? [[String: Any]])
        #expect(tools.count == 1)
        #expect(tools.first?["type"] as? String == "web_search")
        #expect(body?["tool_choice"] as? String == "auto")   // required breaks the Responses server tool loop (live eval 2026-07-31)
        #expect((body?["reasoning"] as? [String: String])?["effort"] == "medium")
        #expect(body?["enable_search"] == nil)
        #expect(body?["enable_thinking"] == nil)
    }
}

// MARK: - Response parsing

struct LLMResponseParsingTests {
    @Test func extractsPlainFencedAndProseWrapped() {
        #expect(LLMResponseParsing.jsonObject(from: #"{"text":"a","changes":[]}"#)?["text"] as? String == "a")
        let fenced = "```json\n{\"text\":\"b\",\"changes\":[\"x\"]}\n```"
        #expect(LLMResponseParsing.jsonObject(from: fenced)?["text"] as? String == "b")
        let prosey = "好的,结果如下:{\"text\":\"c\",\"changes\":[]} 完成"
        #expect(LLMResponseParsing.jsonObject(from: prosey)?["text"] as? String == "c")
        #expect(LLMResponseParsing.jsonObject(from: "no json here") == nil)
    }

    // 2026-07-31 live eval：qwen3.7-flash 意图计划 4 次里 2 次在合法对象后多吐一个悬空
    // `}`（raw-clue-announced-correct-1/3.json 签名），first-{…last-} 切片把它带进载荷，
    // 严格解码必然沉没 → safeUnavailable。切片改为字符串感知的配平扫描。
    @Test func straysTrailingBrace_isSlicedToBalancedObject() throws {
        let raw = """
        {"version": 1,
         "decision": "render",
         "units": [
          {"source": {"exactQuote": "给我的学生何振杰写封邮件。", "range": {"length": 13, "location": 0}, "sourceID": "source-0000"}, "role": "content"}],
         "supersessions": [],
         "entities": ["entity-0000"]}
        }
        """
        let data = try #require(LLMResponseParsing.jsonData(from: raw))
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(obj["version"] as? Int == 1)
        #expect(obj["decision"] as? String == "render")
    }

    @Test func fencedObjectWithTrailingJunk_stillDecodes() throws {
        let raw = "```json\n{\"a\": 1}\n}\n```"
        let obj = try #require(LLMResponseParsing.jsonObject(from: raw))
        #expect(obj["a"] as? Int == 1)
    }

    @Test func bracesInsideStringValues_doNotEndTheScan() throws {
        let raw = #"{"quote": "口播说“先 { 后 } 再 }”", "n": 2} 尾注"#
        let obj = try #require(LLMResponseParsing.jsonObject(from: raw))
        #expect(obj["n"] as? Int == 2)
        #expect((obj["quote"] as? String)?.contains("}") == true)
    }

    @Test func escapedQuoteInsideString_doesNotBreakStringTracking() throws {
        let raw = #"{"quote": "he said \"}\" loudly", "ok": true}}"#
        let obj = try #require(LLMResponseParsing.jsonObject(from: raw))
        #expect(obj["ok"] as? Bool == true)
    }

    @Test func truncatedPayload_keepsLegacyLastBraceSlice() {
        // 不配平（截断）时保持旧行为：first-{…last-} 切片，交给下游严格解码报错。
        #expect(LLMResponseParsing.slicedJSON(from: #"{"a": {"b": 1}"#) == #"{"a": {"b": 1}"#)
    }
}

struct LLMChatClientStripThinkTests {
    @Test func removesAllBlocks_caseInsensitive_attributeTolerant() {
        #expect(LLMChatClient.stripThink("<think>a</think>X<Think>b</THINK>Y") == "XY")  // multiple + case
        #expect(LLMChatClient.stripThink("<think foo=\"bar\">a</think>Z") == "Z")          // attributes
        #expect(LLMChatClient.stripThink("plain text") == "plain text")
    }

    @Test func unclosedTag_leftIntact() {
        // A truncated <think> with no closing tag is NOT nuked (openless semantics).
        #expect(LLMChatClient.stripThink("<think>truncated reasoning") == "<think>truncated reasoning")
    }
}

// MARK: - End-to-end direct rewrite (stubbed transport)

@Suite(.serialized)
struct DirectTextRewriteAPITests {
    private func endpoint(thinking: Bool = false) -> LLMEndpoint {
        LLMEndpoint(providerId: "qwen", baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
                    model: "qwen-plus", apiKey: "sk-1", thinkingEnabled: thinking)
    }

    @Test func rewrite_parsesEnvelope_fillsOriginalFromInput() async throws {
        LLMStubURLProtocol.status = 200
        LLMStubURLProtocol.data = responsesCompletion(content: #"{"text":"缓存需要调整。","changes":["补标点"]}"#)
        let api = DirectTextRewriteAPI(endpoint: endpoint(), session: llmStubSession())

        let result = try await api.rewrite("缓存 要改一下", tone: .natural)

        #expect(result.text == "缓存需要调整。")
        #expect(result.original == "缓存 要改一下")     // filled from input, not the model
        #expect(result.changes == ["补标点"])
    }

    @Test func rewrite_tolerates_fencedJSON() async throws {
        LLMStubURLProtocol.status = 200
        LLMStubURLProtocol.data = responsesCompletion(content: "```json\n{\"text\":\"ok\",\"changes\":[]}\n```")
        let api = DirectTextRewriteAPI(endpoint: endpoint(), session: llmStubSession())
        let result = try await api.rewrite("x", tone: .natural)
        #expect(result.text == "ok")
    }

    // 325 slice 2 (TDD): a `.pack` style threads end-to-end — its system prompt
    // reaches the real request body, with our faithfulness envelope intact.
    @Test func rewrite_packStyle_systemPromptRidesIntoRequestBody() async throws {
        LLMStubURLProtocol.status = 200
        LLMStubURLProtocol.requestBody = Data()
        LLMStubURLProtocol.data = responsesCompletion(content: #"{"text":"对方未履行还款义务。","changes":[]}"#)
        let pack = StylePack(id: "p", name: "公文体", systemPrompt: "改成规范公文语气。", origin: .localImport)
        let api = DirectTextRewriteAPI(endpoint: endpoint(), session: llmStubSession())

        _ = try await api.rewrite("他不还钱", style: .pack(pack))

        let body = String(decoding: LLMStubURLProtocol.requestBody, as: UTF8.self)
        #expect(body.contains("改成规范公文语气。"))
        #expect(body.contains("公文体"))
        #expect(body.contains("Never translate"))   // envelope survives on the wire
    }

    @Test func rewrite_thinkingFlag_ridesIntoRequestBody() async throws {
        LLMStubURLProtocol.status = 200
        LLMStubURLProtocol.requestBody = Data()
        LLMStubURLProtocol.data = responsesCompletion(content: #"{"text":"y","changes":[]}"#)
        let api = DirectTextRewriteAPI(endpoint: endpoint(thinking: true), session: llmStubSession())

        _ = try await api.rewrite("x", tone: .formal)

        let body = try JSONSerialization.jsonObject(with: LLMStubURLProtocol.requestBody) as? [String: Any]
        #expect((body?["reasoning"] as? [String: String])?["effort"] == "medium")
        #expect(body?["enable_thinking"] == nil)
        #expect(LLMStubURLProtocol.requestURL?.path == "/compatible-mode/v1/responses")
    }

    @Test func rewrite_throwsHTTPErrorOnNon2xx() async throws {
        LLMStubURLProtocol.status = 401
        LLMStubURLProtocol.data = #"{"error":"bad key"}"#.data(using: .utf8)!
        let api = DirectTextRewriteAPI(endpoint: endpoint(), session: llmStubSession())
        await #expect(throws: LLMError.self) { _ = try await api.rewrite("x", tone: .natural) }
    }
}
