import ResponsayCore

extension OCRTextCleanupAction {
    var undoActionName: String {
        switch self {
        case .chinesePunctuation: "中文标点"
        case .englishPunctuation: "英文标点"
        case .cjkSpacing: "清理中文间空格"
        }
    }
}
