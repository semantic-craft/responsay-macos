import Foundation

/// App-direct 重改写 (tracer 239, epic 238): builds the rewrite prompt on the client and calls
/// the BYOK provider's OpenAI-compatible endpoint straight — no backend hop. Conforms to the
/// same `TextRewriteAPI` the backend client (`HTTPTextRewriteAPI`) did, so call sites swap
/// transparently; the app picks Direct vs HTTP by whether the LLM card is configured.
public struct DirectTextRewriteAPI: TextRewriteAPI {
    let endpoint: LLMEndpoint
    let client: LLMChatClient

    public init(endpoint: LLMEndpoint, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.client = LLMChatClient(session: session)
    }

    public func rewrite(_ text: String, style: RewriteStyle) async throws -> PolishResult {
        try await rewrite(text, style: style, context: nil)
    }

    /// 屏幕上下文 (context) rides along as an auxiliary block when 屏幕上下文 is enabled.
    public func rewrite(_ text: String, style: RewriteStyle, context: String?) async throws -> PolishResult {
        let prompt = RewritePromptBuilder.build(text: text, style: style, context: context)
        let request = try LLMChatRequestBuilder.makeRequest(
            endpoint: endpoint, system: prompt.system, user: prompt.user,
            responseFormat: LLMResponseFormat.textChanges,
            generationAction: .rewrite)
        let raw = try await client.execute(request)
        // Prefer the {text, changes} envelope; accept a cleaned plain-text reply when the model
        // ignored it. 表达升级's bundled skill explicitly asks for plain-text output, so a fast
        // model often drops the JSON wrapper — throwing badJSON here would fail the whole rewrite
        // and keep the verbatim transcript. Same tolerant path as 轻改写 (`DirectTextPolishAPI`).
        // `original` is filled from the input (the envelope has no "original").
        guard let result = PolishPlainTextFallback.result(fromRaw: raw, input: text) else {
            throw LLMError.badJSON(String(raw.prefix(200)))
        }
        return result
    }
}
