import Foundation

public struct IntentSourceUnit: Codable, Sendable, Equatable {
    public let id: String
    public let originalText: String
    public let utf16Range: IntentSourceRange
    public let comparisonKey: String

    public init(
        id: String,
        originalText: String,
        utf16Range: IntentSourceRange,
        comparisonKey: String
    ) {
        self.id = id
        self.originalText = originalText
        self.utf16Range = utf16Range
        self.comparisonKey = comparisonKey
    }
}
