import Foundation

/// App-direct 划词翻译 (241, epic 238): builds the translate prompt on the client and calls the
/// BYOK provider straight. Same `TextTranslationAPI` the backend client used, so call sites
/// swap transparently.
public struct DirectTextTranslationAPI: TextTranslationAPI {
    let endpoint: LLMEndpoint
    let client: LLMChatClient

    public init(endpoint: LLMEndpoint, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.client = LLMChatClient(session: session)
    }

    public func translate(
        _ text: String,
        target: TranslationTargetLanguage,
        style: TextTranslationStyle
    ) async throws -> TranslationResult {
        try await translate(text, target: target, style: style, context: nil)
    }

    /// 屏幕上下文 (context) rides along as an auxiliary block when 屏幕上下文 is enabled.
    public func translate(
        _ text: String,
        target: TranslationTargetLanguage,
        style: TextTranslationStyle,
        context: String?
    ) async throws -> TranslationResult {
        let prompt = TranslatePromptBuilder.build(text: text, target: target, style: style, context: context)
        let request = try LLMChatRequestBuilder.makeRequest(
            endpoint: endpoint, system: prompt.system, user: prompt.user,
            responseFormat: LLMResponseFormat.textNotes,
            generationAction: .translate)
        let raw = try await client.execute(request)
        guard let obj = LLMResponseParsing.jsonObject(from: raw) else {
            throw LLMError.badJSON(String(raw.prefix(200)))
        }
        let outText = LLMResponseParsing.string(obj, "text")
        guard !outText.isEmpty else { throw LLMError.badJSON("missing \"text\"") }
        return TranslationResult(
            text: outText,
            original: text,
            targetLanguage: target.rawValue,
            notes: LLMResponseParsing.stringArray(obj, "notes"))
    }
}
