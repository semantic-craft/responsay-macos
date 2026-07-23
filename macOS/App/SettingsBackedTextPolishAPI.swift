import Foundation
import OSLog
import ResponsayCore

/// Settings-backed 轻改写 client. App-direct only (epic 238, tracer 239): if the BYOK
/// 「模型与密钥」LLM card is configured, call the chosen provider straight.
struct SettingsBackedTextPolishAPI: TextPolishAPI {
    /// Release-visible log (the `Diag` panel feed is `#if DEBUG`-only). A polish failure makes the
    /// dictation transformer silently degrade to the unpunctuated verbatim transcript, so it must
    /// leave a breadcrumb in the unified log — descriptors only (model + error), never user text.
    private let log = Logger(subsystem: AppBrand.loggerSubsystem, category: "polish")

    /// Injectable for tests; defaults to the real BYOK cloud resolution.
    var resolveEndpoint: @Sendable () -> LLMEndpoint? = { LLMEndpointResolver.resolveText() }

    func polish(_ text: String) async throws -> PolishResult {
        try await polish(text, styleHint: nil)
    }

    func polish(_ text: String, styleHint: String?) async throws -> PolishResult {
        try await polish(text, styleHint: styleHint, context: nil)
    }

    /// 418 — carry the active 日常办公 pack's register into the polish call (additive).
    /// 屏幕上下文 (context) rides along when enabled.
    func polish(_ text: String, styleHint: String?, context: String?) async throws -> PolishResult {
        guard let endpoint = resolveEndpoint() else {
            // #390: no LLM configured → keep the verbatim transcript (纯听写), no error.
            Diag.llm(.info, "polish passthrough — no LLM configured")
            return PolishResult(text: text, original: text)
        }
        Diag.llm(.info, "polish start", fields: ["model": endpoint.model])
        do {
            let result = try await DirectTextPolishAPI(endpoint: endpoint).polish(text, styleHint: styleHint, context: context)
            Diag.llm(.info, "polish done", fields: ["model": endpoint.model])
            return result
        } catch {
            Diag.llm(.error, "polish failed", fields: ["model": endpoint.model], error: error.localizedDescription)
            log.error("polish failed (model \(endpoint.model, privacy: .public)) → dictation kept verbatim, no punctuation: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
}
