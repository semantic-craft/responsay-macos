import ResponsayCore

extension ShortcutAction {
    var title: String {
        switch self {
        case .raw:
            "听写"
        case .translate:
            "听写翻译"
        case .polish:
            "改写原话"
        case .expressInEnglish:
            "地道外文"
        case .rewriteSelection:
            "选中文本改写"
        case .translateSelection:
            "选中文本翻译"
        case .snapOCR:
            "截图翻译"
        case .snapTextOCR:
            "截图取字"
        case .snapImageCopy:
            "截图复制"
        case .askAnything:
            "任意提问"
        case .selectionMenu:
            "划词菜单"
        case .readAloudSelection:
            "朗读选中文本"
        case .openApp:
            "打开 \(AppBrand.displayName)"
        case .openSettings:
            "打开设置"
        case .confirmInsert:
            "确认插入"
        }
    }

    var subtitle: String {
        switch self {
        case .raw:
            "自然说话，\(AppBrand.displayName)会把语音转成干净文本，保留原语言。"
        case .translate:
            "说中文或原文，忠实准确地翻译成目标语言；不做地道外文讲解。"
        case .polish:
            "不翻译，按原语言改写"
        case .expressInEnglish:
            "用蹩脚的英语 / 德语 / 日语说，得到 Native Speaker 的地道说法 + 中文讲解；比听写翻译更意译，重说本意而非逐字直译。"
        case .translateSelection:
            "按原意跨语种转换选区；只做翻译，不给地道外文讲解"
        case .snapOCR:
            "框选屏幕 → OCR 取字 → 忠实准确翻译（图片、PDF、其他应用）"
        case .snapTextOCR:
            "框选屏幕 → OCR 取字 → 复制或弹出可编辑结果（只取字，不翻译）"
        case .snapImageCopy:
            "框选屏幕 → 直接把图片本身复制到剪贴板（不取字、不翻译）"
        case .askAnything:
            "语音问任何事；选中文本时基于选区改写/摘要/翻译/问答"
        case .selectionMenu:
            "选中文字后按快捷键，在光标处弹出菜单：来源核验、翻译、朗读、加入识别词典等。"
        case .readAloudSelection:
            "选中文字后直接朗读，屏底出现控制胶囊；点胶囊上的 ⤢ 打开阅读器窗口，可粘贴长文、调语速换音色。"
        default:
            rawValue
        }
    }

    static var visibleInShortcutSettings: [ShortcutAction] {
        [
            .raw,
            .translate,
            .askAnything,
            .polish,
            .expressInEnglish,
            .rewriteSelection,
            .snapOCR,
            .snapTextOCR,
            .snapImageCopy,
            // legalPalette (选中文本法律技能) removed with 划词技能互动: activated skills surface in
            // the 划词菜单 (.selectionMenu) and route by each skill's `interaction`. A persisted
            // legalPalette binding migrates to .selectionMenu (see ShortcutAction decode).
            .selectionMenu,
            .readAloudSelection,
            .openApp,
            .openSettings,
            .confirmInsert
        ]
    }

}
