import Foundation

/// "Validate" for the App-direct LLM path (240, epic 238). Unlike a `GET /models` reachability
/// ping, this sends a tiny REAL chat completion through the exact path production uses, so it
/// also catches "model name wrong / model rejects this request shape" — openless's Validate
/// semantics. Public entry point because `LLMChatRequestBuilder`/`LLMChatClient` are internal.
public enum LLMConnectivityCheck {
    /// Returns the model's (trimmed) reply on success; throws `LLMError` on failure.
    public static func validate(endpoint: LLMEndpoint, session: URLSession = .shared) async throws -> String {
        let request = try LLMChatRequestBuilder.makeRequest(
            endpoint: endpoint,
            system: "You are a connectivity check. Reply with exactly: OK",
            user: "ping",
            generationAction: .connectivity,
            timeout: 15)
        return try await LLMChatClient(session: session).execute(request)
    }
}
