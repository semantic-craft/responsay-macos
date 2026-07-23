import Foundation

public enum InsertPolicy: String, Codable, Sendable, Equatable {
    case insertImmediately
    case replaceSelection
    case copyOnly
    case noInsert
}
