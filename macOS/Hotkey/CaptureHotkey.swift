import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    // No default normal-shortcut bindings. The app ships Fn-centered: the only
    // out-of-the-box trigger is Fn → 语音输入 (seeded in `ShortcutSettingsStore`,
    // Fn enabled by default). Every normal slot below starts empty; users assign
    // their own in Settings if they want non-Fn shortcuts. See ADR-0018.

    /// Basic dictation (原样输入). slot-0 normal binding — empty by default.
    static let basicDictation = Self("basicDictation")

    /// Translate/rewrite dictation. Empty by default.
    static let rewriteDictation = Self("rewriteDictation")

    /// Rewrite the selected text in the frontmost app. Empty by default.
    static let rewriteSelection = Self("rewriteSelection")

    /// Translate the selected text in the frontmost app. Empty by default.
    static let translateSelection = Self("translateSelection")

    /// Auto-insert idiomatic text, then open the coach card (写入并讲解). Empty by default.
    static let teachingMode = Self("teachingMode")

    /// Express Chinese/rough intent in idiomatic English. Empty by default.
    static let englishExpressionMode = Self("englishExpressionMode")
}
