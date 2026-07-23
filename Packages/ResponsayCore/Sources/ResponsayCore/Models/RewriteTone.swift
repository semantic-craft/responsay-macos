import Foundation

/// Tone preset shared by the 改写 / 表达纠正 rewrite actions.
///
/// User-selectable tone for a rewrite request.
public enum RewriteTone: String, Codable, Sendable, Equatable, CaseIterable {
    case natural
    case casual
    case formal
    case structured
    case concise

    /// Chinese label for the tone-picker chips.
    public var title: String {
        switch self {
        case .natural:    return "自然"
        case .casual:     return "口语"
        case .formal:     return "正式"
        case .structured: return "结构化"
        case .concise:    return "更简短"
        }
    }

    /// Tolerant decode: an unknown backend value falls back to `.natural`
    /// rather than failing the whole result.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RewriteTone(rawValue: raw.lowercased()) ?? .natural
    }
}
