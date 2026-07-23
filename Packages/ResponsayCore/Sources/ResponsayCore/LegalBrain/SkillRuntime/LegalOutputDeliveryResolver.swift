import Foundation

// MARK: - 475 法律输出双态

/// User's preferred shape for a run legal skill's output. Persisted (default `.card`).
public enum LegalOutputModePreference: String, Codable, Sendable, CaseIterable {
    case card     // 卡片：进浮窗，可复制 / 逐项插入（默认）
    case insert   // 直接上屏：把正文经现成 insert 出口写到光标 / 替换选区
}

/// How to deliver this run's output.
public enum LegalOutputDelivery: Sendable, Equatable {
    case card
    case insert(text: String)
}

/// Pure decision: card (default) vs 直接上屏. The secure-input guard (#052) and the
/// "nothing substantive to push → fall back to card" rule live here so they are testable
/// without the macOS insert path.
public struct LegalOutputDeliveryResolver: Sendable {
    public init() {}

    public func resolve(
        preference: LegalOutputModePreference,
        isSecureInput: Bool,
        response: LegalSkillResponse
    ) -> LegalOutputDelivery {
        guard preference == .insert else { return .card }
        guard !isSecureInput else { return .card }   // #052 — never 上屏 into a secure field
        let body = LegalCardRenderer().affordances(for: response).first { $0.kind == .body }
        guard let body else { return .card }
        return .insert(text: body.text)
    }
}
