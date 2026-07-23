import Foundation
import ResponsayCore

/// The default 教练语域 (CoachRegister) applied to the English Coach — read fresh on each
/// invocation by `SettingsBackedCoachAPI` so both Coach entry points (改成地道外文 selection
/// and the speech coach) follow the picker without re-wiring. Set in the 改写设置 screen.
/// Default 口语 (`.casual`) preserves the Coach's original behavior. Mirrors `RewriteStyleSettings`.
enum CoachRegisterSettings {
    /// UserDefaults key shared with the 教练语域 picker (`@AppStorage`).
    static let key = "coach.defaultRegister"

    /// `defaults` is injectable (#494) so the read + derive is unit-testable without polluting
    /// `.standard`; existing call sites omit it. The richer exemplar of this pattern (with
    /// migration) is `ExpressInsertSettings`.
    static func selectedRegister(defaults: UserDefaults = .standard) -> CoachRegister {
        CoachRegister.resolve(stored: defaults.string(forKey: key))
    }
}
