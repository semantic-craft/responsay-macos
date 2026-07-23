import Foundation

public enum Tone: String, Codable, Sendable {
    case fall, rise, fallRise = "fall-rise", riseFall = "rise-fall", level
}
public enum Link: String, Codable, Sendable { case liaison, elision, intrusion }

public struct Word: Codable, Identifiable, Sendable {
    public let id = UUID()
    public let text: String
    public let syllables: [String]
    public let stressIndex: Int?
    public let stressed: Bool
    public let nuclear: Bool
    public let ipa: String?
    public let linkToNext: Link?
    enum CodingKeys: String, CodingKey {
        case text, syllables, stressIndex, stressed, nuclear, ipa, linkToNext
    }
}

/// Compatibility alias: the iOS renderer refers to this type as `ProsodyWord`.
public typealias ProsodyWord = Word

public struct ThoughtGroup: Codable, Sendable { public let tone: Tone; public let words: [Word] }
public struct ProsodyAnalysis: Codable, Sendable {
    public let text: String
    public let isGeneratedExample: Bool
    public let sourceWord: String?
    public let ipa: String
    public let thoughtGroups: [ThoughtGroup]
    public let notes: String?
}
