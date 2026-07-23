import Foundation
import ResponsayCore

/// 截图翻译 target language (UserDefaults-backed). Default `.auto` resolves direction per captured
/// text against the user's 第一语言（母语）/ 第二语言（外语） pair: foreign screenshot → 母语,
/// 母语 screenshot → 外语. See `SnapTranslateTarget` + `TranslationTargetSettings`.
enum SnapTranslateTargetSettings {
    static let key = "snapTranslateTarget"
    static let defaultTarget = SnapTranslateTarget.auto

    static func selected() -> SnapTranslateTarget {
        guard let raw = UserDefaults.standard.string(forKey: key),
              let target = SnapTranslateTarget(rawValue: raw) else {
            return defaultTarget
        }
        return target
    }

    /// The concrete language to translate `text` into, honouring the saved choice + auto-direction
    /// against the user's 第一语言（母语）/ 第二语言（外语） pair.
    static func resolve(for text: String) -> TranslationTargetLanguage {
        selected().resolved(
            for: text,
            primary: TranslationTargetSettings.primaryLanguage(),
            secondary: TranslationTargetSettings.secondaryLanguage())
    }
}

/// 截图取字 (snapTextOCR) result handling. Off (default) → show the editable result panel.
/// On → copy the recognized text straight to the clipboard, no panel (the classic 截图复制 behavior).
enum SnapOCRCopySettings {
    static let key = "snapOCRCopyToClipboard"

    static var copyToClipboard: Bool {
        UserDefaults.standard.bool(forKey: key)
    }
}

/// 截图复制 (snapImageCopy) completion cue. On (default) → play a short chime once the image lands
/// on the clipboard, so the user knows the silent, panel-less copy succeeded.
enum SnapCopySoundSettings {
    static let key = "snapCopySoundEnabled"

    /// Default ON. `object(forKey:) == nil` → never set → treat as enabled.
    static var enabled: Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }
}
