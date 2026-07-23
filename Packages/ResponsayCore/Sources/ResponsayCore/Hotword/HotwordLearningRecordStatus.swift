import Foundation

public enum HotwordLearningRecordStatus: String, Sendable, Codable, Equatable, CaseIterable {
    case pending
    case added
    case ignored
    case undone
}
