import Foundation

/// Builds the provider's preferred OpenAI-compatible text request for the App-direct path
/// (epic 238): Qwen uses `/responses`; the remaining providers keep `/chat/completions`.
/// Pure + synchronous: the whole `[String: Any]` body is assembled and serialized here, before
/// any `await`, so nothing non-Sendable crosses an async boundary.
///
/// We deliberately do NOT send `response_format` json_schema: OpenAI honors it but several
/// BYOK providers 400 on it. The prompts already demand "one JSON object as raw text" and
/// `LLMResponseParsing` extracts it tolerantly — one path that works across every provider.
enum LLMChatRequestBuilder {
    /// `responseFormat` (json_schema) is included ONLY for a local endpoint (Ollama needs it for
    /// valid JSON; cloud providers may 400 on it). `timeout == nil` resolves to 300s for a local
    /// endpoint (cold model load is tens of seconds) and 60s for cloud.
    static func makeRequest(
        endpoint: LLMEndpoint,
        system: String,
        user: String,
        responseFormat: [String: Any]? = nil,
        searchEnabled: Bool = false,
        generationAction: LLMGenerationAction = .rewrite,
        timeout: TimeInterval? = nil
    ) throws -> URLRequest {
        guard endpoint.isConfigured else { throw LLMError.notConfigured }
        try MiMoLLMRouteGuard.validate(endpoint: endpoint)
        let capabilities = LLMProviderCapabilities.resolve(
            providerId: endpoint.providerId,
            baseURLHost: endpoint.host)
        let usesResponses = LLMProviderCapabilities.prefersResponses(
            providerId: endpoint.providerId,
            baseURLHost: endpoint.host)
        let url = usesResponses
            ? LLMWire.responsesURL(base: endpoint.baseURL)
            : LLMWire.chatCompletionsURL(base: endpoint.baseURL)
        guard let url else { throw LLMError.invalidEndpoint(endpoint.baseURL) }
        let profile = LLMGenerationProfile.resolve(
            providerId: endpoint.providerId,
            baseURLHost: endpoint.host,
            action: generationAction)

        var body: [String: Any] = ["model": endpoint.model, "stream": false]
        // 百炼 Responses 的 store 默认是 true，会保留响应 7 天供 response_id 检索。
        // App 自己传完整上下文且不使用服务端响应续接，因此显式关闭远端响应存储。
        if usesResponses { body["store"] = false }
        let messages = [
            ["role": "system", "content": system],
            ["role": "user", "content": user],
        ]
        body[usesResponses ? "input" : "messages"] = messages
        for (key, value) in profile.requestBody(capabilities: capabilities) { body[key] = value }
        // 思考(thinking) params — each provider's official channel, default off. Qwen
        // Responses uses `reasoning.effort`; legacy Chat-only providers retain their own fields.
        let thinking = LLMThinkingControl.extraBody(
            providerId: endpoint.providerId, model: endpoint.model,
            baseURLHost: endpoint.host, enabled: endpoint.thinkingEnabled, streaming: false)
        for (key, value) in thinking { body[key] = value }
        // Web search is opt-in per request. Qwen Responses uses the official bare web_search tool;
        // Chat-only providers retain their documented shapes.
        let search = LLMSearchControl.extraBody(
            providerId: endpoint.providerId, baseURLHost: endpoint.host,
            searchEnabled: searchEnabled)
        for (key, value) in search { body[key] = value }
        // json_schema only helps (and is only safe) on the local runner.
        if endpoint.isLocal, let responseFormat { body["response_format"] = responseFormat }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in LLMWire.authHeaders(providerId: endpoint.providerId, key: endpoint.apiKey) {
            req.setValue(value, forHTTPHeaderField: key)
        }
        req.timeoutInterval = timeout ?? profile.timeout
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }
}
