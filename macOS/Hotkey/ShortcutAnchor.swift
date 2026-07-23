enum ShortcutAnchor: String, Codable, Hashable, Identifiable, Sendable, CaseIterable {
    case fn
    case rightOption

    var id: String { rawValue }

    var displayString: String {
        switch self {
        case .fn:
            "Fn"
        case .rightOption:
            "右 Option"
        }
    }

    var title: String {
        switch self {
        case .fn:
            "Fn 键"
        case .rightOption:
            "右 Option 键"
        }
    }

    var enableLabel: String {
        switch self {
        case .fn:
            "启用 Fn / 地球键"
        case .rightOption:
            "启用右 Option 键"
        }
    }

    var addLabel: String {
        switch self {
        case .fn:
            "添加 Fn 快捷键"
        case .rightOption:
            "添加右 Option 快捷键"
        }
    }

    var systemImage: String {
        switch self {
        case .fn:
            "globe"
        case .rightOption:
            "option"
        }
    }
}
