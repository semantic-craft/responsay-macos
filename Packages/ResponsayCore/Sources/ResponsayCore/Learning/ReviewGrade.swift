import Foundation

public enum ReviewGrade: Int, CaseIterable, Codable, Identifiable, Sendable {
    case blackout = 0
    case wrong = 1
    case hard = 2
    case hesitant = 3
    case good = 4
    case easy = 5

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .blackout: "忘了"
        case .wrong: "不对"
        case .hard: "吃力"
        case .hesitant: "想起"
        case .good: "记得"
        case .easy: "熟了"
        }
    }
}
