import Foundation

public struct IntentPlanSourceReference: Codable, Sendable, Equatable {
    public let sourceID: String
    public let range: IntentSourceRange
    public let exactQuote: String

    public init(sourceID: String, range: IntentSourceRange, exactQuote: String) {
        self.sourceID = sourceID
        self.range = range
        self.exactQuote = exactQuote
    }

    public init(_ source: IntentSourceUnit) {
        self.init(
            sourceID: source.id,
            range: source.utf16Range,
            exactQuote: source.originalText)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case sourceID, range, exactQuote
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownIntentKeys(in: decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceID = try container.decode(String.self, forKey: .sourceID)
        range = try container.decode(IntentSourceRange.self, forKey: .range)
        exactQuote = try container.decode(String.self, forKey: .exactQuote)
    }
}
