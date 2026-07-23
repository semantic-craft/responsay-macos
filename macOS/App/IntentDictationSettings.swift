import Foundation

/// 校验成稿（实验）开关的单一真相源（558；spec 2026-07-10 §35）。默认关。
/// 开启后，默认听写 trigger（`.raw` 动作）在轻度改写档上路由到 Intent-aware Dictate；
/// 「如实输入」仍是逃生口——用户显式选如实（关轻度改写）时，本开关不生效。
/// 这里只管 mode 路由；编译器可用性由 `IntentCompilationPipeline` 的 route policy 再把一道门。
enum IntentDictationSettings {
    /// 未设置过 → 缺省 `false`（实验功能，显式启用）。
    static let key = "dictation.intentAware"
    /// 564 — 可选第二阶段润色（只作用于已验证 sanitized draft）。默认关：
    /// 关闭时 sanitized-draft 路线即完整路线；开启后润色失败仍退回 sanitized draft。
    static let optionalPolishKey = "dictation.intentAware.optionalPolish"

    static func isEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) as? Bool ?? false
    }

    static func setEnabled(_ enabled: Bool, _ defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: key)
    }

    static func isOptionalPolishEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: optionalPolishKey) as? Bool ?? false
    }
}
