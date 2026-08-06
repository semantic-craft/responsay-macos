import Foundation

/// Legacy adapter for the old `fnCombo.*` UserDefaults keys.
///
/// New code reads and writes `ShortcutSettingsStore`. This type intentionally keeps only the
/// migration surface so older builds can still read their keys if the app is rolled back.
enum FnComboSettings {
    static func legacyHasStoredCombo(
        for action: ShortcutAction,
        defaults: UserDefaults = .standard
    ) -> Bool {
        legacyKeys(for: action)
            .contains { defaults.object(forKey: $0) != nil }
    }

    static func legacyStoredCombo(
        for action: ShortcutAction,
        defaults: UserDefaults = .standard
    ) -> FnChord? {
        for key in legacyKeys(for: action) {
            guard defaults.object(forKey: key) != nil else {
                continue
            }

            return parseLegacy(defaults.string(forKey: key) ?? "none")
        }

        return nil
    }

    static func legacyDefaultCombo(for action: ShortcutAction) -> FnChord? {
        switch action {
        case .raw:
            .fnOnly
        case .translate:
            .fnShift
        case .expressInEnglish:
            nil
        case .translateSelection:
            nil
        case .askAnything:
            .fnSpace
        case .selectionMenu:
            // New 划词菜单 action — Fn+V out of the box, so a fresh install's legacy-seed
            // path (no snapshot yet) gets it just like raw / translate / 任意提问 do.
            .fnV
        case .readAloudSelection:
            // 朗读选中文本 — Fn+R out of the box, same fresh-install seeding as 划词菜单.
            .fnR
        default:
            nil
        }
    }

    private static func legacyKeys(for action: ShortcutAction) -> [String] {
        switch action {
        case .raw:
            ["fnCombo.raw"]
        case .translate:
            []
        case .polish:
            ["fnCombo.polish", "fnCombo.rewriteDictation"]
        case .expressInEnglish:
            // Includes the retired `coach` action's legacy keys so a 表达教练 Fn combo
            // migrates onto the merged 地道外文 action.
            ["fnCombo.expressInEnglish", "fnCombo.englishExpressionMode",
             "fnCombo.coach", "fnCombo.teachingMode"]
        case .rewriteSelection:
            ["fnCombo.rewriteSelection"]
        case .translateSelection:
            ["fnCombo.translateSelection"]
        case .snapOCR:
            []   // new action — no legacy `fnCombo.*` key ever existed to migrate
        case .snapTextOCR:
            []   // new action — no legacy `fnCombo.*` key ever existed to migrate
        case .snapImageCopy:
            []   // new action — no legacy `fnCombo.*` key ever existed to migrate
        case .askAnything:
            ["fnCombo.askAnything"]
        case .selectionMenu:
            []   // new action — no legacy `fnCombo.*` key ever existed to migrate
        case .readAloudSelection:
            []   // new action — no legacy `fnCombo.*` key ever existed to migrate
        case .openApp:
            ["fnCombo.openApp"]
        case .openSettings:
            ["fnCombo.openSettings"]
        case .confirmInsert:
            ["fnCombo.confirmInsert"]
        }
    }

    private static func parseLegacy(_ raw: String) -> FnChord? {
        switch raw {
        case "fn":
            .fnOnly
        case "fn+shift":
            .fnShift
        case "fn+option":
            .fnOption
        case "fn+control":
            .fnControl
        case "fn+command":
            .fnCommand
        default:
            nil
        }
    }
}
