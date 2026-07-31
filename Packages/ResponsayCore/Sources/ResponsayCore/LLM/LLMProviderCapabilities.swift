import Foundation

public enum LLMGenerationAction: Sendable, Equatable {
    case polish
    case rewrite
    case translate
    case express
    case ask
    case connectivity
}

public struct LLMProviderCapabilities: Sendable, Equatable {
    public enum BuiltinTool: Sendable, Equatable, Hashable {
        case webSearch
        case webExtractor
        case codeInterpreter
        case knowledgeRetrieval
        case mcp
    }

    public enum AuthHeaderStyle: Sendable, Equatable {
        case bearer
        case apiKeyHeader(String)

        func headers(key: String?) -> [String: String] {
            guard let key, !key.isEmpty else { return [:] }
            switch self {
            case .bearer:
                return ["Authorization": "Bearer \(key)"]
            case let .apiKeyHeader(name):
                return [name: key]
            }
        }
    }

    public enum ThinkingControl: Sendable, Equatable {
        case none
        case enableThinking
        case reasoningEffort
        case thinkingObject
        case openRouterReasoning
        case ollamaReasoning
    }

    public let supportsChatCompletions: Bool
    public let supportsResponses: Bool
    public let supportsStreamUsage: Bool
    public let supportsThinkingControl: Bool
    public let supportsJSONMode: Bool
    public let supportsPartialMode: Bool
    public let supportsContextCache: Bool
    public let supportsBatch: Bool
    public let builtinTools: Set<BuiltinTool>
    public let authHeaderStyle: AuthHeaderStyle
    public let thinkingControl: ThinkingControl
    public let allowsGenerationParameters: Bool

    public static func resolve(providerId: String, baseURLHost: String) -> LLMProviderCapabilities {
        switch channel(providerId: providerId, host: baseURLHost) {
        case .qwen:
            return .init(
                supportsChatCompletions: true,
                supportsResponses: true,
                supportsStreamUsage: false,
                supportsThinkingControl: true,
                supportsJSONMode: false,
                supportsPartialMode: true,
                supportsContextCache: true,
                supportsBatch: true,
                builtinTools: [.webSearch, .webExtractor, .codeInterpreter, .knowledgeRetrieval, .mcp],
                authHeaderStyle: .bearer,
                thinkingControl: .reasoningEffort,
                allowsGenerationParameters: true)
        case .mimo:
            return .init(
                supportsChatCompletions: true,
                supportsResponses: false,
                supportsStreamUsage: false,
                supportsThinkingControl: true,
                supportsJSONMode: false,
                supportsPartialMode: false,
                supportsContextCache: false,
                supportsBatch: false,
                builtinTools: [.webSearch],
                authHeaderStyle: .apiKeyHeader("api-key"),
                thinkingControl: .thinkingObject,
                allowsGenerationParameters: true)
        case .zhipu:
            return .init(
                supportsChatCompletions: true,
                supportsResponses: false,
                supportsStreamUsage: false,
                supportsThinkingControl: true,
                supportsJSONMode: false,
                supportsPartialMode: false,
                supportsContextCache: false,
                supportsBatch: false,
                builtinTools: [.webSearch],
                authHeaderStyle: .bearer,
                thinkingControl: .thinkingObject,
                allowsGenerationParameters: true)
        case .doubao:
            return .init(
                supportsChatCompletions: true,
                supportsResponses: true,
                supportsStreamUsage: true,
                supportsThinkingControl: true,
                supportsJSONMode: false,
                supportsPartialMode: false,
                supportsContextCache: false,
                supportsBatch: false,
                builtinTools: [.webSearch],
                authHeaderStyle: .bearer,
                thinkingControl: .thinkingObject,
                allowsGenerationParameters: true)
        case .gemini:
            return .init(
                supportsChatCompletions: true,
                supportsResponses: false,
                supportsStreamUsage: false,
                supportsThinkingControl: true,
                supportsJSONMode: false,
                supportsPartialMode: false,
                supportsContextCache: false,
                supportsBatch: false,
                builtinTools: [],
                authHeaderStyle: .bearer,
                thinkingControl: .reasoningEffort,
                allowsGenerationParameters: true)
        case .openai:
            return .init(
                supportsChatCompletions: true,
                supportsResponses: true,
                supportsStreamUsage: false,
                supportsThinkingControl: true,
                supportsJSONMode: true,
                supportsPartialMode: false,
                supportsContextCache: false,
                supportsBatch: true,
                builtinTools: [.webSearch, .codeInterpreter],
                authHeaderStyle: .bearer,
                thinkingControl: .reasoningEffort,
                allowsGenerationParameters: true)
        case .openrouter:
            return .init(
                supportsChatCompletions: true,
                supportsResponses: false,
                supportsStreamUsage: false,
                supportsThinkingControl: true,
                supportsJSONMode: false,
                supportsPartialMode: false,
                supportsContextCache: false,
                supportsBatch: false,
                builtinTools: [],
                authHeaderStyle: .bearer,
                thinkingControl: .openRouterReasoning,
                allowsGenerationParameters: true)
        case .ollama:
            return .init(
                supportsChatCompletions: true,
                supportsResponses: false,
                supportsStreamUsage: false,
                supportsThinkingControl: true,
                supportsJSONMode: true,
                supportsPartialMode: false,
                supportsContextCache: false,
                supportsBatch: false,
                builtinTools: [],
                authHeaderStyle: .bearer,
                thinkingControl: .ollamaReasoning,
                allowsGenerationParameters: true)
        case .otherKnown:
            return .init(
                supportsChatCompletions: true,
                supportsResponses: false,
                supportsStreamUsage: false,
                supportsThinkingControl: false,
                supportsJSONMode: false,
                supportsPartialMode: false,
                supportsContextCache: false,
                supportsBatch: false,
                builtinTools: [],
                authHeaderStyle: .bearer,
                thinkingControl: .none,
                allowsGenerationParameters: true)
        case .unknown:
            return .init(
                supportsChatCompletions: true,
                supportsResponses: false,
                supportsStreamUsage: false,
                supportsThinkingControl: false,
                supportsJSONMode: false,
                supportsPartialMode: false,
                supportsContextCache: false,
                supportsBatch: false,
                builtinTools: [],
                authHeaderStyle: .bearer,
                thinkingControl: .none,
                allowsGenerationParameters: false)
        }
    }

    /// Qwen's current text models use the provider's OpenAI-compatible Responses API for all
    /// production generation paths. Other providers retain their existing ordinary-generation
    /// route; Doubao/OpenAI still opt into Responses only in their dedicated search adapter.
    public static func prefersResponses(providerId: String, baseURLHost: String) -> Bool {
        channel(providerId: providerId, host: baseURLHost) == .qwen
    }

    private enum Channel { case qwen, mimo, zhipu, doubao, gemini, openai, openrouter, ollama, otherKnown, unknown }

    private static func channel(providerId: String, host: String) -> Channel {
        switch providerId.lowercased() {
        case "qwen", "qwen-team": return .qwen
        case "mimo", "mimo-payg": return .mimo
        case "zhipu": return .zhipu
        case "doubao": return .doubao
        case "gemini": return .gemini
        case "openai": return .openai
        case "ollama": return .ollama
        case "deepseek", "minimax": return .otherKnown
        case "custom": break
        default: break
        }

        let h = host.lowercased()
        if h.contains("dashscope") || h.contains("aliyuncs") { return .qwen }
        if h.contains("xiaomimimo") { return .mimo }
        if h.contains("bigmodel") { return .zhipu }
        if h.contains("volces") || h.contains("volcengine") { return .doubao }
        if h.contains("generativelanguage") { return .gemini }
        if h == "api.openai.com" { return .openai }
        if h.contains("openrouter") { return .openrouter }
        if h == "localhost" || h == "127.0.0.1" { return .ollama }
        if h.contains("deepseek") || h.contains("minimax") { return .otherKnown }
        return .unknown
    }
}

public struct LLMGenerationProfile: Sendable, Equatable {
    public let temperature: Double?
    public let topP: Double?
    public let maxCompletionTokens: Int?
    public let frequencyPenalty: Double?
    public let presencePenalty: Double?
    public let timeout: TimeInterval
    public let thinkingDefault: Bool

    public init(
        temperature: Double?,
        topP: Double?,
        maxCompletionTokens: Int?,
        frequencyPenalty: Double? = nil,
        presencePenalty: Double? = nil,
        timeout: TimeInterval,
        thinkingDefault: Bool
    ) {
        self.temperature = temperature
        self.topP = topP
        self.maxCompletionTokens = maxCompletionTokens
        self.frequencyPenalty = frequencyPenalty
        self.presencePenalty = presencePenalty
        self.timeout = timeout
        self.thinkingDefault = thinkingDefault
    }

    public static func resolve(
        providerId: String,
        baseURLHost: String,
        action: LLMGenerationAction
    ) -> LLMGenerationProfile {
        let pid = providerId.lowercased()
        let host = baseURLHost.lowercased()
        if pid == "mimo" || pid == "mimo-payg" || host.contains("xiaomimimo") {
            return .init(
                temperature: 1.0,
                topP: 0.95,
                maxCompletionTokens: 1024,
                frequencyPenalty: 0,
                presencePenalty: 0,
                timeout: 60,
                thinkingDefault: false)
        }
        if pid == "qwen" || pid == "qwen-team" || host.contains("dashscope") || host.contains("aliyuncs") {
            // 百炼 Responses 建议 temperature / top_p 只设置一个；保留低温度以维持
            // 改写与翻译的确定性，不再同时发送 top_p。
            return .init(temperature: 0.2, topP: nil, maxCompletionTokens: nil, timeout: 60, thinkingDefault: false)
        }
        if pid == "ollama" || host == "localhost" || host == "127.0.0.1" {
            return .init(temperature: 0.2, topP: 0.8, maxCompletionTokens: nil, timeout: 300, thinkingDefault: false)
        }
        switch action {
        case .translate:
            return .init(temperature: 0.2, topP: nil, maxCompletionTokens: nil, timeout: 60, thinkingDefault: false)
        case .express:
            return .init(temperature: 0.4, topP: 0.9, maxCompletionTokens: nil, timeout: 60, thinkingDefault: false)
        case .ask, .connectivity, .polish, .rewrite:
            return .init(temperature: 0.2, topP: 0.8, maxCompletionTokens: nil, timeout: 60, thinkingDefault: false)
        }
    }

    func requestBody(capabilities: LLMProviderCapabilities) -> [String: Any] {
        guard capabilities.allowsGenerationParameters else { return [:] }
        var body: [String: Any] = [:]
        if let temperature { body["temperature"] = temperature }
        if let topP { body["top_p"] = topP }
        if let maxCompletionTokens { body["max_completion_tokens"] = maxCompletionTokens }
        if let frequencyPenalty { body["frequency_penalty"] = frequencyPenalty }
        if let presencePenalty { body["presence_penalty"] = presencePenalty }
        return body
    }
}
