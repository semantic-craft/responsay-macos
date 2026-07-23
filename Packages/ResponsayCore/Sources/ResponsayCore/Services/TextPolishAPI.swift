import Foundation

public protocol TextPolishAPI: Sendable {
    func polish(_ text: String) async throws -> PolishResult
    /// 418 — polish with an optional register hint from the active 日常办公 style pack.
    /// Conformers that don't override get the default below (hint ignored), so existing
    /// call sites and mocks stay source-compatible.
    func polish(_ text: String, styleHint: String?) async throws -> PolishResult
    /// 屏幕上下文 — optional auxiliary context block injected into the polish prompt. Default
    /// forwards to the styleHint overload (context ignored), so existing conformers/mocks
    /// stay source-compatible.
    func polish(_ text: String, styleHint: String?, context: String?) async throws -> PolishResult
}

public extension TextPolishAPI {
    func polish(_ text: String, styleHint: String?) async throws -> PolishResult {
        try await polish(text)
    }
    func polish(_ text: String, styleHint: String?, context: String?) async throws -> PolishResult {
        try await polish(text, styleHint: styleHint)
    }
}
