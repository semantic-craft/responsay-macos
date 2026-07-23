import Foundation
import ResponsayCore

/// One selectable 译文服务 in the 截图翻译 panel: a configured (keyed) LLM provider the user can
/// translate with, so they can switch services and compare wordings.
struct SnapTranslateService: Identifiable, Equatable, Sendable {
    let id: String      // providerId (ProviderCatalog preset id)
    let name: String    // 显示名（displayName(for: .llm)）
}

/// 译文失败时给用户看的人读消息。`String` 不能直接当 `Error`，用它承载，所以翻译闭包能返回
/// `Result<String, SnapTranslateError>`。
struct SnapTranslateError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Builds the 译文服务 picker list for 截图翻译 — the LLM providers the user has a key for, in
/// catalog order — and picks the default (current) service. Pure given an injected
/// `ProviderConfigDispatcher`, so it unit-tests without the real Keychain.
enum SnapTranslateServiceCatalog {

    /// Configured (keyed) cloud LLM providers, in the catalog's display order. Empty when none
    /// has a key — but 截图翻译 is gated by `requireTextModel` upstream, so in practice the current
    /// provider is always present here.
    static func services(dispatcher: ProviderConfigDispatcher = ProviderConfigDispatcher()) -> [SnapTranslateService] {
        ProviderCatalog.presets(for: .llm).compactMap { preset in
            guard dispatcher.resolve(.llm, providerId: preset.id).hasKey else { return nil }
            return SnapTranslateService(id: preset.id, name: preset.displayName(for: .llm))
        }
    }

    /// The service to translate with first: the user's current LLM provider when it's keyed,
    /// else the first keyed provider, else `nil` (nothing configured).
    static func defaultServiceId(
        defaults: UserDefaults = .standard,
        dispatcher: ProviderConfigDispatcher = ProviderConfigDispatcher()
    ) -> String? {
        let available = services(dispatcher: dispatcher)
        let currentBase = ModelRouteOptionID.parse(ModelRouteCatalog.currentLLMId(defaults: defaults)).base
        if available.contains(where: { $0.id == currentBase }) { return currentBase }
        return available.first?.id
    }
}
