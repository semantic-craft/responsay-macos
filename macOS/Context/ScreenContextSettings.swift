import Foundation

/// 屏幕上下文 (screen context) master switch — lives in 技能偏好, default ON.
///
/// When ON, the focused-field context plus the recursively-collected visible on-screen text
/// (`VisibleTextCollector`) are attached to the **cloud** LLM prompts (地道外文 + 任意提问) so the
/// model can "see" what the user is looking at. When OFF, no screen-derived context is sent to the
/// cloud; local hotword biasing and skill routing read context independently and are unaffected.
///
/// Reads the same UserDefaults key as the `@AppStorage` toggle in `SettingsLegalConfigPane`, so the
/// non-view capture path and the settings switch stay in sync.
enum ScreenContextSettings {
    static let key = "context.screenEnabled"

    /// Default ON: absent key → enabled.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }
}
