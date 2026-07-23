import Foundation

/// A half-open character range `[start, end)` into the *original* text, marking
/// where a rewrite issue applies. Decodes both `{start,end}` and
/// `{location,length}` shapes; repaired against the real text before use.
public struct TextSpan: Codable, Sendable, Equatable {
    public let start: Int
    public let end: Int

    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }

    private enum CodingKeys: String, CodingKey {
        case start, end, location, length
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try c.decodeIfPresent(Int.self, forKey: .start),
           let e = try c.decodeIfPresent(Int.self, forKey: .end) {
            start = s
            end = e
        } else if let loc = try c.decodeIfPresent(Int.self, forKey: .location),
                  let len = try c.decodeIfPresent(Int.self, forKey: .length) {
            start = loc
            end = loc + len
        } else {
            start = 0
            end = 0
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(start, forKey: .start)
        try c.encode(end, forKey: .end)
    }

    /// `true` when the span points at a real, non-empty, in-bounds range.
    public func isValid(within length: Int) -> Bool {
        start >= 0 && end <= length && start < end
    }

    /// Clamp the span into `[0, length]`, preserving order. Returns `nil` when
    /// nothing valid remains (e.g. `start >= end` after clamping).
    public func clamped(within length: Int) -> TextSpan? {
        let lo = max(0, min(start, length))
        let hi = max(0, min(end, length))
        guard lo < hi else { return nil }
        return TextSpan(start: lo, end: hi)
    }
}

/// Problem category attached to a span. Tolerant: unknown labels parse to `.other`.
public enum IssueLabel: String, Codable, Sendable, Equatable, CaseIterable {
    case grammar
    case wordChoice
    case tone
    case clarity
    case idiom
    case other

    public var title: String {
        switch self {
        case .grammar:    return "语法"
        case .wordChoice: return "用词"
        case .tone:       return "语气"
        case .clarity:    return "清晰度"
        case .idiom:      return "地道度"
        case .other:      return "其他"
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = IssueLabel.parse(raw)
    }

    static func parse(_ raw: String) -> IssueLabel {
        let key = raw.lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        switch key {
        case "grammar", "grammatical":
            return .grammar
        case "wordchoice", "word", "diction", "collocation":
            return .wordChoice
        case "tone", "register":
            return .tone
        case "clarity", "clear", "concise", "wordy":
            return .clarity
        case "idiom", "idiomatic", "naturalness", "natural":
            return .idiom
        default:
            return .other
        }
    }
}

/// One flagged span in the original, with its category and a short note.
public struct RewriteIssue: Decodable, Sendable, Equatable {
    public let span: TextSpan
    public let label: IssueLabel
    public let note: String

    public init(span: TextSpan, label: IssueLabel, note: String = "") {
        self.span = span
        self.label = label
        self.note = note
    }

    private enum CodingKeys: String, CodingKey {
        case span, label, note, message, text
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        span = try c.decode(TextSpan.self, forKey: .span)
        label = try c.decodeIfPresent(IssueLabel.self, forKey: .label) ?? .other
        note = try (c.decodeIfPresent(String.self, forKey: .note))
            ?? (c.decodeIfPresent(String.self, forKey: .message))
            ?? (c.decodeIfPresent(String.self, forKey: .text))
            ?? ""
    }
}
