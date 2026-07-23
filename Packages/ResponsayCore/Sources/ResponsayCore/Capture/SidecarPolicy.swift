import Foundation

public enum SidecarPolicy: String, Codable, Sendable, Equatable {
    case none
    case collapsed
    case badgeOnly
    case highlight
    case autoOpenCoach
    case autoOpenProsody
    case autoOpenPractice
}
