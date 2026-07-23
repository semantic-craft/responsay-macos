import Foundation

/// App-direct Intent-aware plan compiler (#558): calls the user's configured BYOK LLM endpoint
/// straight (OpenAI-compatible `/chat/completions`, epic 238) and returns the provider's JSON
/// plan bytes for the strict `IntentPlan` decoder. This is the ONLY tolerant step on the intent
/// path — unwrapping a ```json fence around the object — and it is transport unwrapping, not a
/// content fallback: a response without a decodable plan object throws, and the pipeline turns
/// every throw into `safe-unavailable` with zero insertion. No plain-text fallback exists here
/// (unlike `PolishPlainTextFallback`), per spec decision 11.
public struct DirectIntentPlanAPI: IntentPlanCompiler {
    let endpoint: LLMEndpoint
    let client: LLMChatClient

    public init(endpoint: LLMEndpoint, session: URLSession = .shared) {
        // 思考 forced OFF regardless of the user's global toggle (435 precedent): plan
        // compilation needs low-latency, clean JSON content, and DashScope hard-400s on
        // `enable_thinking:true` for non-streaming calls anyway.
        self.endpoint = LLMEndpoint(
            providerId: endpoint.providerId,
            baseURL: endpoint.baseURL,
            model: endpoint.model,
            apiKey: endpoint.apiKey,
            thinkingEnabled: false)
        self.client = LLMChatClient(session: session)
    }

    public func compile(_ input: IntentCompilerInput) async throws -> Data {
        let prompt = IntentPlanPromptBuilder.build(input)
        let request = try LLMChatRequestBuilder.makeRequest(
            endpoint: endpoint, system: prompt.system, user: prompt.user,
            // #566: the strict plan contract runs unchanged on a local runner. json_object mode is
            // sent ONLY when `endpoint.isLocal` (the builder gate); cloud providers that 400 on it
            // never see it, keeping ONE compiler for both routes (no weaker local bypass).
            responseFormat: LLMResponseFormat.jsonObject,
            generationAction: .polish)
        let raw: String
        do {
            raw = try await client.execute(request)
        } catch {
            // A cancelled capture must surface as `.cancelled`, not `.compilerFailed` —
            // `LLMChatClient` folds URLError.cancelled into `LLMError.network`.
            try Task.checkCancellation()
            throw sanitizedProviderError(error)
        }
        guard let data = LLMResponseParsing.jsonData(from: raw) else {
            throw LLMError.badJSON("intent plan response did not contain a JSON object")
        }
        return data
    }

    /// Intent errors may reach diagnostics at the app boundary. Provider response bodies are
    /// untrusted user-adjacent content, so strip them before the error leaves this API. A LOCAL
    /// runner's 4xx (model not installed, `response_format` unsupported) is a *capability* fault,
    /// not a transient outage — surface it as `capabilityUnsupported` (#566: 能力不达 → safe-unavailable,
    /// 不静默改走云端), so the capsule tells the user to switch model rather than offering a retry.
    private func sanitizedProviderError(_ error: any Error) -> any Error {
        guard let error = error as? LLMError else { return error }
        switch error {
        case .http(let status, _):
            if endpoint.isLocal, (400..<500).contains(status) {
                return IntentCompilerFailure(.capabilityUnsupported)
            }
            return LLMError.http(status: status, body: "")
        case .badJSON:
            return LLMError.badJSON("intent plan response was rejected")
        default:
            return error
        }
    }
}
