enum ShortcutAction: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case raw
    case translate
    case polish
    case expressInEnglish
    case rewriteSelection
    case translateSelection
    case snapOCR
    case snapTextOCR
    case snapImageCopy
    case askAnything
    case selectionMenu
    case readAloudSelection
    case openApp
    case openSettings
    case confirmInsert

    var id: String { rawValue }

    /// Lenient decode so a binding persisted under a retired action migrates instead of
    /// throwing — a throw would fail the whole `[ShortcutBinding]` snapshot decode and
    /// silently reset every binding. Retired actions:
    ///   • `coach` (英文表达 / 表达教练 merged into 地道外文) → `expressInEnglish`
    ///   • `legalPalette` (选中文本法律技能 retired with 划词技能互动; skills now run from the
    ///     划词菜单) → `selectionMenu`, its functional successor.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "coach":
            self = .expressInEnglish
        case "legalPalette":
            self = .selectionMenu
        default:
            guard let action = Self(rawValue: rawValue) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unknown shortcut action: \(rawValue)")
            }
            self = action
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
