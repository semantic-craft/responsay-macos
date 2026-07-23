import Foundation

/// One pre-numbered, whitelisted entity candidate (#562, spec decisions 15/16). Built ON DEVICE
/// before compilation from allowed grounding sources only; the compiler may select a candidate
/// by `id` but can never author `value` or move `target`. The slot (`target`) is app-computed —
/// the model cannot choose where a replacement lands.
public struct IntentEntityCandidate: Sendable, Equatable {
    /// Whitelist provenance — the ONLY admissible candidate sources (spec decision 15).
    /// Contacts, the open web, model world-knowledge and cross-session memory are not cases
    /// here by design; a candidate without one of these origins cannot exist.
    public enum Provenance: String, Sendable, Equatable {
        case spokenClue
        case dictionary
        case confirmedAlias
        case allowedContext

        /// Short, content-free evidence label for the review capsule (#559 sidecar).
        public var evidenceLabel: String {
            switch self {
            case .spokenClue: return "口述释字"
            case .dictionary: return "词典"
            case .confirmedAlias: return "已确认别名"
            case .allowedContext: return "屏幕上下文"
            }
        }
    }

    public let id: String
    /// The canonical replacement text. Enters the final draft only through the deterministic
    /// source renderer, and is re-checked by the post-render guard.
    public let value: String
    public let provenance: Provenance
    /// The exact transcript span this candidate replaces (always within ONE source unit).
    public let target: IntentPlanSourceReference

    public init(
        id: String,
        value: String,
        provenance: Provenance,
        target: IntentPlanSourceReference
    ) {
        self.id = id
        self.value = value
        self.provenance = provenance
        self.target = target
    }
}
