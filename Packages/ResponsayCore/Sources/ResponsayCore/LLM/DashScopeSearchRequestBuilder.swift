import Foundation

/// Builds DashScope native text-generation requests for source-returning web search.
/// The OpenAI-compatible Qwen route can search, but DashScope native is the route
/// that returns `output.search_info.search_results` for legal verification URLs.
enum DashScopeSearchRequestBuilder {
    static func supportsNativeSourceSearch(providerId: String, baseURLHost: String) -> Bool {
        let id = providerId.lowercased()
        let host = baseURLHost.lowercased()
        guard id == "qwen" || id == "qwen-team" || host.contains("dashscope") else { return false }
        return host.contains("dashscope")
    }

    static func makeRequest(
        endpoint: LLMEndpoint,
        system: String,
        user: String,
        timeout: TimeInterval = 90
    ) throws -> URLRequest {
        guard endpoint.isConfigured else { throw LLMError.notConfigured }
        guard let url = generationURL(base: endpoint.baseURL) else {
            throw LLMError.invalidEndpoint(endpoint.baseURL)
        }

        var messages: [[String: String]] = []
        if !system.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append(["role": "system", "content": system])
        }
        messages.append(["role": "user", "content": user])

        let body: [String: Any] = [
            "model": endpoint.model,
            "input": ["messages": messages],
            "parameters": [
                "enable_search": true,
                "search_options": [
                    "forced_search": true,
                    "search_strategy": searchStrategy(for: endpoint.model),
                    "enable_source": true,
                ],
                "result_format": "message",
            ],
        ]

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

    static func generationURL(base: String) -> URL? {
        guard var components = URLComponents(string: base.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = components.host?.lowercased(),
              host.contains("dashscope") else {
            return nil
        }
        components.path = "/api/v1/services/aigc/text-generation/generation"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private static func searchStrategy(for model: String) -> String {
        let m = model.lowercased()
        if m.contains("qwen3-max") || m.contains("omni") {
            return "agent"
        }
        return "max"
    }
}
