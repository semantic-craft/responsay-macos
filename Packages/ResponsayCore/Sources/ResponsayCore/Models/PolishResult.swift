import Foundation

public struct PolishResult: Codable, Sendable, Equatable {
    public let text: String
    public let original: String
    public let changes: [String]

    public init(text: String, original: String, changes: [String] = []) {
        self.text = text
        self.original = original
        self.changes = changes
    }
}
