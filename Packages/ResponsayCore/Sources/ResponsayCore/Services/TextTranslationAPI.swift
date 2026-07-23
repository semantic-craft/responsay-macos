import Foundation

public enum TextTranslationStyle: Sendable, Equatable {
    case literal
    case nativeIntent
}

public protocol TextTranslationAPI: Sendable {
    func translate(_ text: String, target: TranslationTargetLanguage, style: TextTranslationStyle) async throws -> TranslationResult
    /// 屏幕上下文 — optional auxiliary context block injected into the translate prompt. Default
    /// forwards to the contextless overload, so existing conformers/mocks stay source-compatible.
    func translate(_ text: String, target: TranslationTargetLanguage, style: TextTranslationStyle, context: String?) async throws -> TranslationResult
}

extension TextTranslationAPI {
    public func translate(_ text: String, target: TranslationTargetLanguage) async throws -> TranslationResult {
        try await translate(text, target: target, style: .literal)
    }
    public func translate(_ text: String, target: TranslationTargetLanguage, style: TextTranslationStyle, context: String?) async throws -> TranslationResult {
        try await translate(text, target: target, style: style)
    }
}
