import Foundation

public protocol CoachAPI: Sendable {
    func express(_ intent: String, context: ExpressionContext?, target: TranslationTargetLanguage) async throws -> ExpressionResult
    func ask(_ question: String, context: String) async throws -> ExpressionResult
}

public extension CoachAPI {
    func express(_ intent: String, context: ExpressionContext?) async throws -> ExpressionResult {
        try await express(intent, context: context, target: .englishUS)
    }

    func express(_ intent: String) async throws -> ExpressionResult {
        try await express(intent, context: nil, target: .englishUS)
    }
}

public enum CoachAPIError: LocalizedError {
    case message(String)
    public var errorDescription: String? {
        switch self { case .message(let m): return m }
    }
}
