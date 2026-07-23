import Foundation

/// Builds the OpenAI-compatible `/chat/completions` request for the App-direct path
/// (epic 238). Pure + synchronous: the whole `[String: Any]` body is assembled and serialized
/// here, before any `await`, so nothing non-Sendable crosses an async boundary.
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
        guard let url = LLMWire.chatCompletionsURL(base: endpoint.baseURL) else {
            throw LLMError.invalidEndpoint(endpoint.baseURL)
        }
        let capabilities = LLMProviderCapabilities.resolve(
            providerId: endpoint.providerId,
            baseURLHost: endpoint.host)
        let profile = LLMGenerationProfile.resolve(
            providerId: endpoint.providerId,
            baseURLHost: endpoint.host,
            action: generationAction)

        var body: [String: Any] = [
            "model": endpoint.model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
            "stream": false,
        ]
        for (key, value) in profile.requestBody(capabilities: capabilities) { body[key] = value }
        // 思考(thinking) params — each provider's official channel, default off.
        let thinking = LLMThinkingControl.extraBody(
            providerId: endpoint.providerId, model: endpoint.model,
            baseURLHost: endpoint.host, enabled: endpoint.thinkingEnabled, streaming: false)
        for (key, value) in thinking { body[key] = value }
        // Web search is opt-in per request. Apply it after thinking so providers
        // such as Kimi/MiMo can force thinking disabled while search tools are enabled.
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
