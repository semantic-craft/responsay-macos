import Foundation

/// User-facing category for a note explaining a correction or rewrite.
public enum WhyKind: String, Codable, Sendable, Equatable, CaseIterable {
    case tone          // 语气
    case perspective   // 视角
    case register      // 场景 / 语域

    public var title: String {
        switch self {
        case .tone:        return "语气"
        case .perspective: return "视角"
        case .register:    return "场景"
        }
    }

    /// Accepts English keys (`tone`) and the Chinese labels (`语气`); unknown
    /// values fall back to `.tone` so one odd note never drops the result.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WhyKind.parse(raw)
    }

    static func parse(_ raw: String) -> WhyKind {
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "tone", "语气":
            return .tone
        case "perspective", "视角", "viewpoint":
            return .perspective
        case "register", "scene", "场景", "语域":
            return .register
        default:
            return .tone
        }
    }
}

/// One「为什么这样改」note: a category plus a one-line Chinese explanation.
public struct WhyNote: Codable, Sendable, Equatable {
    public let kind: WhyKind
    public let text: String

    public init(kind: WhyKind, text: String) {
        self.kind = kind
        self.text = text
    }
}
