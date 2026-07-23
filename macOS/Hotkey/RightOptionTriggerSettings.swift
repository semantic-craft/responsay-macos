import Foundation

/// Which capture function the standalone **right-Option** trigger fires. Single source of
/// truth for the controller (event time) and the settings picker.
///
/// - key absent → the out-of-box default (`地道外文` / expressInEnglish), so right-Option
///   works on a fresh install per the locked design.
/// - key == `disabledSentinel` → right-Option is off (no function).
/// - otherwise → the stored `ShortcutAction` rawValue.
enum RightOptionTriggerSettings {
    static let key = "shortcut.rightOptionAction"
    static let disabledSentinel = "none"

    /// Default for a fresh install: tap right-Option → 地道外文.
    static let defaultAction: ShortcutAction = .expressInEnglish

    static func action(defaults: UserDefaults = .standard) -> ShortcutAction? {
        guard let raw = defaults.string(forKey: key) else { return defaultAction }
        if raw == disabledSentinel { return nil }
        return ShortcutAction(rawValue: raw) ?? defaultAction
    }

    static func setAction(_ action: ShortcutAction?, defaults: UserDefaults = .standard) {
        defaults.set(action?.rawValue ?? disabledSentinel, forKey: key)
    }
}
