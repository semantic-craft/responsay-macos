import Foundation
import ResponsayCore

struct SettingsBackedTextTranslationAPI: TextTranslationAPI {
    /// Injectable for tests; defaults to the real BYOK cloud resolution.
    var resolveEndpoint: @Sendable () -> LLMEndpoint? = { LLMEndpointResolver.resolveText() }

    func translate(
        _ text: String,
        target: TranslationTargetLanguage,
        style: TextTranslationStyle
    ) async throws -> TranslationResult {
        try await translate(text, target: target, style: style, context: nil)
    }

    /// 屏幕上下文 (context) rides along when enabled.
    func translate(
        _ text: String,
        target: TranslationTargetLanguage,
        style: TextTranslationStyle,
        context: String?
    ) async throws -> TranslationResult {
        guard let endpoint = resolveEndpoint() else {
            Diag.llm(.info, "translate blocked — no LLM configured", fields: ["target": target.rawValue])
            throw LLMEndpointResolver.notConfigured
        }
        Diag.llm(.info, "translate start", fields: ["target": target.rawValue, "style": "\(style)", "model": endpoint.model])
        do {
            let result = try await DirectTextTranslationAPI(endpoint: endpoint).translate(text, target: target, style: style, context: context)
            Diag.llm(.info, "translate done", fields: ["model": endpoint.model])
            return result
        } catch {
            Diag.llm(.error, "translate failed", fields: ["target": target.rawValue, "model": endpoint.model], error: error.localizedDescription)
            throw error
        }
    }
}
