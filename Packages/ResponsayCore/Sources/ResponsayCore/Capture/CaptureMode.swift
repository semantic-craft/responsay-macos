import Foundation

public enum CaptureMode: String, CaseIterable, Codable, Sendable, Equatable {
    case raw
    case polishSameLanguage
    case intentAwareDictation
    case expressInEnglish
    case coach
    case rewriteSelection
    case translateSelection
    /// Legal palette mode (105): trigger the legal candidate palette on the active
    /// selection. `insertPolicy = .noInsert` — selecting a card runs a skill, not insert.
    case legal

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "polish", "polishedTranscript":
            self = .polishSameLanguage
        case "teaching", "teachingFeedback", "englishExpression":
            self = .expressInEnglish
        default:
            guard let mode = Self(rawValue: rawValue) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unknown capture mode: \(rawValue)")
            }
            self = mode
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
