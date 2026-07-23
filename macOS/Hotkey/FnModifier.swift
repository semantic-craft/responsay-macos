enum FnModifier: String, CaseIterable, Codable, Hashable, Sendable {
    case shift
    case option
    case control
    case command

    var symbol: String {
        switch self {
        case .shift:
            "⇧"
        case .option:
            "⌥"
        case .control:
            "⌃"
        case .command:
            "⌘"
        }
    }
}

extension Set where Element == FnModifier {
    var sortedForDisplay: [FnModifier] {
        FnModifier.allCases.filter { contains($0) }
    }
}
