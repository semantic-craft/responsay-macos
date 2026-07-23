import Foundation
import ResponsayCore

/// The 改写策略 (ExpressRewriteStrategy) applied to 地道外文 — read fresh on each invocation by
/// `SettingsBackedCoachAPI`, so the Coach follows the picker without re-wiring. Set in the
/// 改写设置 screen, next to 教练语域. Default 原意优先 (`.faithful`) preserves faithful behaviour.
/// Mirrors `CoachRegisterSettings`. Key is independent of `coach.defaultRegister` /
/// `rewrite.defaultTone` / the 日常办公 active-skill key.
enum ExpressRewriteStrategySettings {
    /// UserDefaults key shared with the 改写策略 picker (`@AppStorage`).
    static let key = "coach.rewriteStrategy"

    static func selectedStrategy() -> ExpressRewriteStrategy {
        ExpressRewriteStrategy.resolve(stored: UserDefaults.standard.string(forKey: key))
    }
}
