import Foundation

/// App-direct 轻改写 (tracer 239, epic 238): builds the polish prompt on the client and calls
/// the BYOK provider's OpenAI-compatible endpoint straight — no backend hop. Conforms to the
/// same `TextPolishAPI` the backend client (`HTTPTextPolishAPI`) did, so call sites swap
/// transparently; the app picks Direct vs HTTP by whether the LLM card is configured.
public struct DirectTextPolishAPI: TextPolishAPI {
    let endpoint: LLMEndpoint
    let client: LLMChatClient

    public init(endpoint: LLMEndpoint, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.client = LLMChatClient(session: session)
    }

    public func polish(_ text: String) async throws -> PolishResult {
        try await polish(text, styleHint: nil, context: nil)
    }

    public func polish(_ text: String, styleHint: String?) async throws -> PolishResult {
        try await polish(text, styleHint: styleHint, context: nil)
    }

    /// 418 — thread the active 日常办公 pack's register into the polish prompt (additive nudge).
    /// 屏幕上下文 (context) rides along as an auxiliary block when 屏幕上下文 is enabled.
    public func polish(_ text: String, styleHint: String?, context: String?) async throws -> PolishResult {
        let prompt = PolishPromptBuilder.build(text: text, styleHint: styleHint, context: context)
        let request = try LLMChatRequestBuilder.makeRequest(
            endpoint: endpoint, system: prompt.system, user: prompt.user,
            responseFormat: LLMResponseFormat.textChanges,
            generationAction: .polish)
        let raw = try await client.execute(request)
        // Prefer the {text, changes} envelope; accept a plain-text reply when the model ignored
        // it (small/flash models often do, since the cloud path sends no json_schema). Throwing
        // here would make dictation silently degrade to the unpunctuated verbatim transcript —
        // the "offline dictation has no punctuation" bug. `original` is filled from the input
        // (the envelope has no "original").
        guard let result = PolishPlainTextFallback.result(fromRaw: raw, input: text) else {
            throw LLMError.badJSON(String(raw.prefix(200)))
        }
        return result
    }
}
