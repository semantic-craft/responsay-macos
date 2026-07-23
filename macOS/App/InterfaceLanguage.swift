import AppKit

/// Bridges the 界面语言 picker to the system per-app language override.
/// macOS reads `AppleLanguages` from the app's UserDefaults at launch and picks
/// the matching String Catalog language; switching needs a relaunch (existing
/// `AppRelaunch`) because localized resources load once at launch.
@MainActor
enum InterfaceLanguage {
    static let appleLanguagesKey = "AppleLanguages"

    /// Pure mapping. Explicit language → override array; "system"/unknown → nil (clear = follow system).
    nonisolated static func appleLanguages(for value: String) -> [String]? {
        switch value {
        case "zh-Hans", "en": return [value]
        default: return nil
        }
    }

    /// Apply a newly-selected language: write/clear the override, then offer a relaunch.
    static func apply(_ value: String, defaults: UserDefaults = .standard) {
        if let langs = appleLanguages(for: value) {
            defaults.set(langs, forKey: appleLanguagesKey)
        } else {
            defaults.removeObject(forKey: appleLanguagesKey)
        }
        promptRelaunch()
    }

    private static func promptRelaunch() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = String(localized: "切换界面语言需要重启")
        alert.informativeText = String(localized: "重启后新的界面语言才会生效。")
        alert.addButton(withTitle: String(localized: "立即重启"))
        alert.addButton(withTitle: String(localized: "稍后"))
        if alert.runModal() == .alertFirstButtonReturn {
            AppRelaunch.relaunch()
        }
    }
}
