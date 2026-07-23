import Foundation

/// Style learning (P1): distills a handful of the user's kept dictation outputs into ONE short
/// Chinese style descriptor (语气/句式/正式度/用词/详略), fed into the 智能整理 prompt so polish
/// reads more like the user wrote it. One non-streaming LLM call; the result is a single line.
public struct StyleDistiller: Sendable {
    private let execute: @Sendable (URLRequest) async throws -> String

    public init(execute: @escaping @Sendable (URLRequest) async throws -> String) {
        self.execute = execute
    }

    public init(session: URLSession = .shared) {
        let client = LLMChatClient(session: session)
        self.init { try await client.execute($0) }
    }

    /// `samples` = recent kept dictation outputs. Returns a one-line descriptor, or throws on a
    /// network/parse failure (the caller keeps the previous descriptor).
    public func distill(samples: [String], endpoint: LLMEndpoint) async throws -> String {
        let trimmed = samples
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(20)
            .map { String($0.prefix(200)) }
        guard !trimmed.isEmpty else { return "" }
        let request = try LLMChatRequestBuilder.makeRequest(
            endpoint: endpoint,
            system: Self.systemPrompt,
            user: Self.userPrompt(samples: Array(trimmed)),
            generationAction: .rewrite,
            timeout: 20)
        return Self.clean(try await execute(request))
    }

    static let systemPrompt = """
    你是写作风格分析器。下面是同一位用户保留下来的若干段听写整理结果。用一句中文，从语气、句式长短、\
    正式程度、用词偏好、详略五个方面，概括这位用户的总体表达风格，供「智能整理」参考以更贴近其习惯。
    严格要求：只输出这一句概括，不超过 60 字；不要分点、不要解释、不要引用或复述原文的具体内容、\
    不要提到任何具体人名或事实。
    """

    static func userPrompt(samples: [String]) -> String {
        let body = samples.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")
        return "用户保留的听写结果：\n\(body)"
    }

    /// First non-empty line, trimmed, capped — defends against a model that adds bullets/prose.
    static func clean(_ raw: String) -> String {
        let line = raw
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        return String(line.prefix(80))
    }
}
