import Foundation

/// 教练语域 (Coach register) — the English Coach's Layer-2 axis. Parallel to `RewriteTone`
/// (改写风格) but a distinct concept: every register stays idiomatic SPOKEN English,
/// intent-guessed, and is never a translation. All four are spoken (this is a speaking coach).
///
/// The coaching register selected by the user. The default is `.casual` (口语).
public enum CoachRegister: String, Codable, Sendable, Equatable, CaseIterable {
    case casual
    case neutral
    case formal
    case academic

    /// Chinese label for the 教练语域 picker.
    public var title: String {
        switch self {
        case .casual:   return "口语"
        case .neutral:  return "中性"
        case .formal:   return "正式"
        case .academic: return "学术"
        }
    }

    /// Tolerant decode: an unknown backend value falls back to `.casual` (口语)
    /// rather than failing the whole result. Mirrors `RewriteTone`.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CoachRegister(rawValue: raw.lowercased()) ?? .casual
    }

    /// Resolve a stored register string (e.g. a UserDefaults value) to a register,
    /// defaulting to `.casual` (口语) when missing or unrecognized. Pure so the default
    /// behavior is unit-testable; the app's `CoachRegisterSettings` wraps UserDefaults around it.
    public static func resolve(stored raw: String?) -> CoachRegister {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty else { return .casual }
        return CoachRegister(rawValue: raw) ?? .casual
    }
}
