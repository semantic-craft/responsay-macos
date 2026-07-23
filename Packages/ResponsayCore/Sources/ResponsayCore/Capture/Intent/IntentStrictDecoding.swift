import Foundation

private struct IntentAnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

func rejectUnknownIntentKeys<Keys: CodingKey & CaseIterable>(
    in decoder: Decoder,
    allowed: Keys.Type
) throws where Keys.AllCases: Sequence {
    let container = try decoder.container(keyedBy: IntentAnyCodingKey.self)
    let allowedNames = Set(Keys.allCases.map(\.stringValue))
    let unknownNames = container.allKeys.map(\.stringValue).filter { !allowedNames.contains($0) }
    guard unknownNames.isEmpty else {
        throw DecodingError.dataCorrupted(.init(
            codingPath: decoder.codingPath,
            debugDescription: "Unknown fields: \(unknownNames.sorted().joined(separator: ", "))"))
    }
}
