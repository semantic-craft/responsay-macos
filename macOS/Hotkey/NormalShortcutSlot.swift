import KeyboardShortcuts

struct NormalShortcutSlot: Hashable, Identifiable, Sendable {
    let action: ShortcutAction
    let index: Int

    var id: String {
        "\(action.rawValue).normal.\(index)"
    }

    var name: KeyboardShortcuts.Name {
        switch (action, index) {
        case (.raw, 0):
            .basicDictation
        case (.polish, 0):
            .rewriteDictation
        case (.expressInEnglish, 0):
            .englishExpressionMode
        case (.rewriteSelection, 0):
            .rewriteSelection
        case (.translateSelection, 0):
            .translateSelection
        case (.raw, 1):
            .responsayRawNormal1
        case (.raw, 2):
            .responsayRawNormal2
        case (.polish, 1):
            .responsayPolishNormal1
        case (.polish, 2):
            .responsayPolishNormal2
        case (.expressInEnglish, 1):
            .responsayExpressInEnglishNormal1
        case (.expressInEnglish, 2):
            .responsayExpressInEnglishNormal2
        case (.rewriteSelection, 1):
            .responsayRewriteSelectionNormal1
        case (.rewriteSelection, 2):
            .responsayRewriteSelectionNormal2
        case (.translateSelection, 1):
            .responsayTranslateSelectionNormal1
        case (.translateSelection, 2):
            .responsayTranslateSelectionNormal2
        default:
            // New actions (askAnything / openApp / openSettings / confirmInsert) have no
            // predefined Name — derive a stable, dot-free one
            // (KeyboardShortcuts.Name rawValues must not contain dots; matches the
            // camelCase convention of the named slots above).
            KeyboardShortcuts.Name(
                "responsay\(action.rawValue.prefix(1).uppercased())\(action.rawValue.dropFirst())Normal\(index)")
        }
    }

    static func slots(for action: ShortcutAction) -> [NormalShortcutSlot] {
        (0..<3).map { NormalShortcutSlot(action: action, index: $0) }
    }
}
