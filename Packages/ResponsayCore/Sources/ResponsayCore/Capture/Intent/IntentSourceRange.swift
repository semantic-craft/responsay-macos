import Foundation

public struct IntentSourceRange: Codable, Sendable, Equatable {
    public let location: Int
    public let length: Int

    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case location, length
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownIntentKeys(in: decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        location = try container.decode(Int.self, forKey: .location)
        length = try container.decode(Int.self, forKey: .length)
    }

    func isWithin(utf16Count: Int) -> Bool {
        location >= 0
            && length >= 0
            && location <= utf16Count
            && length <= utf16Count - location
    }

    func isWithin(_ other: IntentSourceRange) -> Bool {
        guard location >= other.location,
              length >= 0,
              other.length >= 0
        else { return false }
        let relativeLocation = location - other.location
        return relativeLocation <= other.length && length <= other.length - relativeLocation
    }

    var nsRange: NSRange { NSRange(location: location, length: length) }
}
