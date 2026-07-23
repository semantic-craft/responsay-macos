import Foundation

/// App-direct English coach (242 express + 244 analyze, epic 238): builds the express /
/// prosody prompts on the client and calls the BYOK provider straight. Conforms to the same
/// `CoachAPI` the backend client did. `register` (教练语域) is supplied by the app from settings.
public struct DirectCoachAPI: CoachAPI {
    let endpoint: LLMEndpoint
    let register: CoachRegister
    let strategy: ExpressRewriteStrategy
    let client: LLMChatClient

    public init(
        endpoint: LLMEndpoint,
        register: CoachRegister,
        strategy: ExpressRewriteStrategy = .faithful,
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.register = register
        self.strategy = strategy
        self.client = LLMChatClient(session: session)
    }

    public func express(
        _ intent: String,
        context: ExpressionContext?,
        target: TranslationTargetLanguage
    ) async throws -> ExpressionResult {
        let prompt = ExpressPromptBuilder.build(
            intent: intent,
            context: context,
            register: register,
            strategy: strategy,
            target: target)
        let request = try LLMChatRequestBuilder.makeRequest(
            endpoint: endpoint, system: prompt.system, user: prompt.user,
            responseFormat: LLMResponseFormat.express,
            generationAction: .express)
        let raw = try await client.execute(request)
        guard let obj = LLMResponseParsing.jsonObject(from: raw) else {
            throw LLMError.badJSON(String(raw.prefix(200)))
        }
        let idiomatic = LLMResponseParsing.string(obj, "idiomatic")
        guard !idiomatic.isEmpty else { throw LLMError.badJSON("missing \"idiomatic\"") }
        return ExpressionResult(
            idiomatic: idiomatic,
            original: intent,
            reasons: LLMResponseParsing.stringArray(obj, "reasons"),
            thinkingShift: LLMResponseParsing.string(obj, "thinkingShift"),
            alternatives: LLMResponseParsing.stringArray(obj, "alternatives"),
            intentNote: LLMResponseParsing.string(obj, "intentNote"))
    }

    public func ask(_ question: String, context: String) async throws -> ExpressionResult {
        let system = "你是一个智能助手。请基于以下提供的参考上下文，回答用户的问题。"
        let user = """
        [上下文开始]
        \(context)
        [上下文结束]
        问题：\(question)
        """
        let request = try LLMChatRequestBuilder.makeRequest(
            endpoint: endpoint, system: system, user: user,
            responseFormat: LLMResponseFormat.express,
            generationAction: .ask)
        let raw = try await client.execute(request)
        guard let obj = LLMResponseParsing.jsonObject(from: raw) else {
            throw LLMError.badJSON(String(raw.prefix(200)))
        }
        let idiomatic = LLMResponseParsing.string(obj, "idiomatic")
        guard !idiomatic.isEmpty else { throw LLMError.badJSON("missing \"idiomatic\"") }
        return ExpressionResult(
            idiomatic: idiomatic,
            original: question,
            reasons: LLMResponseParsing.stringArray(obj, "reasons"),
            thinkingShift: "",
            alternatives: [])
    }
}
