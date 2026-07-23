import Foundation

public enum HotwordConfirmationPolicy: String, Sendable, Codable, Equatable, CaseIterable {
    case confirmEveryTime
    case autoAddHighConfidence
}
