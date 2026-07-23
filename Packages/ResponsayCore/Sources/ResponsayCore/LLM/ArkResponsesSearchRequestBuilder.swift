import Foundation

/// Builds Responses API (`/responses`) requests for source-returning web search. Two providers
/// expose web search on this route: Volcengine Ark (Doubao's plugin) and OpenAI (its native
/// `web_search` tool, the only OpenAI route where chat-latest / gpt-5.x can actually search —
/// `/chat/completions` only searches with the `*-search-preview` models). The Responses event
/// shape + citation annotations are identical (Ark mirrors OpenAI), so the stream parser and
/// `LLMSearchResultParser` are shared; only the request body differs slightly (below).
enum ArkResponsesSearchRequestBuilder {
    static func supportsWebSearch(providerId: String, baseURLHost: String) -> Bool {
        let id = providerId.lowercased()
        let host = baseURLHost.lowercased()
        return id == "doubao" || host.contains("volces") || host.contains("volcengine")
            || isOpenAI(providerId: providerId, baseURLHost: baseURLHost)
    }

    /// OpenAI's `/responses` differs from Ark: no `thinking` field, and the `web_search` tool
    /// takes none of Volcengine's `max_keyword`/`limit` extras (they 400 on OpenAI).
    static func isOpenAI(providerId: String, baseURLHost: String) -> Bool {
        providerId.lowercased() == "openai" || baseURLHost.lowercased().contains("api.openai.com")
    }

    /// The Responses request body shared by the streaming (`DirectArkResponsesStreamingClient`)
    /// and non-streaming (`makeRequest`) callers — single source of truth so the two can't drift.
    static func responsesBody(
        model: String,
        input: [[String: Any]],
        stream: Bool,
        thinkingEnabled: Bool,
        searchEnabled: Bool,
        isOpenAI: Bool
    ) -> [String: Any] {
        var body: [String: Any] = ["model": model, "input": input, "stream": stream]
        if !isOpenAI { body["thinking"] = ["type": thinkingEnabled ? "enabled" : "disabled"] }
        if searchEnabled {
            // max_keyword caps parallel searches (cost); limit caps results per search — both
            // Volcengine-only. OpenAI's tool is bare `{type: web_search}`.
            body["tools"] = [isOpenAI ? ["type": "web_search"]
                                      : ["type": "web_search", "max_keyword": 2, "limit": 3]]
            if !isOpenAI { body["max_tool_calls"] = 3 }
        }
        return body
    }

    static func makeRequest(
        endpoint: LLMEndpoint,
        system: String,
        user: String,
        timeout: TimeInterval = 90
    ) throws -> URLRequest {
        guard endpoint.isConfigured else { throw LLMError.notConfigured }
        guard let url = responsesURL(base: endpoint.baseURL) else {
            throw LLMError.invalidEndpoint(endpoint.baseURL)
        }

        var input: [[String: Any]] = []
        if !system.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            input.append(message(role: "system", text: system))
        }
        input.append(message(role: "user", text: user))

        let body = responsesBody(
            model: endpoint.model,
            input: input,
            stream: false,
            thinkingEnabled: endpoint.thinkingEnabled,
            searchEnabled: true,
            isOpenAI: isOpenAI(providerId: endpoint.providerId, baseURLHost: endpoint.host))

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in LLMWire.authHeaders(providerId: endpoint.providerId, key: endpoint.apiKey) {
            req.setValue(value, forHTTPHeaderField: key)
        }
        req.timeoutInterval = timeout
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    static func responsesURL(base: String) -> URL? {
        var s = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        guard !s.isEmpty else { return nil }
        if s.hasSuffix("/responses") { return URL(string: s) }
        if s.hasSuffix("/chat/completions") {
            s = String(s.dropLast("/chat/completions".count))
        }
        return URL(string: s + "/responses")
    }

    private static func message(role: String, text: String) -> [String: Any] {
        [
            "role": role,
            "content": [[
                "type": "input_text",
                "text": text,
            ]],
        ]
    }
}
