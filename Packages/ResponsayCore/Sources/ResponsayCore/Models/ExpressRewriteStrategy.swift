import Foundation

/// 改写策略 (Express rewrite strategy) — the 地道外文 axis orthogonal to 教练语域
/// (`CoachRegister`). It controls how much liberty the coach takes with the user's *content*:
///
/// - `.faithful` (原意优先, default): upgrade only the wording / structure / naturalness; never
///   change, add to, or second-guess what the user actually said.
/// - `.guessIntent` (猜测意图): additionally allow the coach to reconstruct the single most likely
///   intent when the utterance is tangled / self-contradictory — under hard brakes (no invented
///   facts; fall back to faithful when unsure; never decide for the user).
///
/// Mirrors `CoachRegister` / `RewriteTone`: a pure `resolve(stored:)` so the default is unit-testable,
/// with the app's `ExpressRewriteStrategySettings` wrapping UserDefaults around it.
public enum ExpressRewriteStrategy: String, Codable, Sendable, Equatable, CaseIterable {
    case faithful
    case guessIntent = "guess_intent"

    /// Chinese label for the 改写策略 picker.
    public var title: String {
        switch self {
        case .faithful:    return "原意优先"
        case .guessIntent: return "猜测意图"
        }
    }

    /// Resolve a stored strategy string (e.g. a UserDefaults value) to a strategy, defaulting to
    /// `.faithful` (原意优先) when missing or unrecognized. Tolerant of case.
    public static func resolve(stored raw: String?) -> ExpressRewriteStrategy {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty else { return .faithful }
        return ExpressRewriteStrategy(rawValue: raw) ?? .faithful
    }
}
