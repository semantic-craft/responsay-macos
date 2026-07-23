import Foundation
import ResponsayCore

/// Settings-backed 重改写 client. App-direct first (epic 238, tracer 239): if the BYOK
/// 「模型与密钥」LLM card is configured, call the chosen provider straight (no backend hop,
/// no localhost Node). Heavy rewrite is an explicit model feature, so missing config is
/// surfaced instead of silently returning the original text.
struct SettingsBackedTextRewriteAPI: TextRewriteAPI {
    /// Injectable for tests; defaults to the real BYOK cloud resolution.
    var resolveEndpoint: @Sendable () -> LLMEndpoint? = { LLMEndpointResolver.resolveText() }

    func rewrite(_ text: String, style: RewriteStyle) async throws -> PolishResult {
        try await rewrite(text, style: style, context: nil)
    }

    /// 屏幕上下文 (context) rides along when enabled.
    func rewrite(_ text: String, style: RewriteStyle, context: String?) async throws -> PolishResult {
        let styleLabel = Self.label(for: style)
        guard let endpoint = resolveEndpoint() else {
            Diag.llm(.info, "rewrite blocked — no LLM configured", fields: ["style": styleLabel])
            throw LLMEndpointResolver.notConfigured
        }
        Diag.llm(.info, "rewrite start", fields: ["style": styleLabel, "model": endpoint.model])
        do {
            let result = try await DirectTextRewriteAPI(endpoint: endpoint).rewrite(text, style: style, context: context)
            Diag.llm(.info, "rewrite done", fields: ["model": endpoint.model])
            return result
        } catch {
            Diag.llm(.error, "rewrite failed", fields: ["style": styleLabel, "model": endpoint.model], error: error.localizedDescription)
            throw error
        }
    }

    /// Diagnostics label (no raw pack content — just tone name or pack id).
    private static func label(for style: RewriteStyle) -> String {
        switch style {
        case let .tone(t): return t.rawValue
        case let .pack(p): return "pack:\(p.id)"
        }
    }
}
