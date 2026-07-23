import Foundation

// MARK: - 165 source-verification target schema
//
// The spec-facing authoring / extractor-output shape. It does NOT fork the
// canonical store — it maps onto the built `VerificationKind` / `VerificationStatus`
// / `VerificationAnchor` (issue 108) via `anchorKind` and `toAnchor()`. The
// anchor remains the source of truth; this is the convertible DTO.

/// The verification target vocabulary from the native PRD (spec §12).
public enum VerificationTargetKind: String, Codable, Sendable, CaseIterable {
    case statute
    case caseLaw = "case"
    case article
    case date
    case monetaryRule
    case doctrinalClaim

    /// Lower onto the canonical `VerificationKind` (no fork).
    public var anchorKind: VerificationKind {
        switch self {
        case .statute: return .law
        case .caseLaw: return .caseLaw
        case .article: return .scholarlyArticle
        case .date: return .date
        case .monetaryRule: return .money
        case .doctrinalClaim: return .other
        }
    }
}

/// Coarse three-state outcome the UI tracks (spec §12), aligned to the richer
/// built `VerificationStatus`.
public enum VerificationOutcome: String, Codable, Sendable, CaseIterable {
    case pending
    case verified
    case rejected

    /// The `[待核]`-style tag rendered next to the label.
    public var tag: String {
        switch self {
        case .pending: return "[待核]"
        case .verified: return "[已核]"
        case .rejected: return "[已驳]"
        }
    }

    public init(_ status: VerificationStatus) {
        switch status {
        case .pending: self = .pending
        case .rejected: self = .rejected
        case .verifiedLaw, .verifiedCase, .scholarlyReference, .userConfirmed: self = .verified
        }
    }
}

/// A source-verification target. Defaults to `.pending` → renders `[待核]`
/// until verified. `suggestedQueries` seed the verification launcher.
public struct VerificationTarget: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let label: String
    public let kind: VerificationTargetKind
    public var status: VerificationOutcome
    public let suggestedQueries: [String]

    public init(
        id: String,
        label: String,
        kind: VerificationTargetKind,
        status: VerificationOutcome = .pending,
        suggestedQueries: [String] = []
    ) {
        self.id = id
        self.label = label
        self.kind = kind
        self.status = status
        self.suggestedQueries = suggestedQueries
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, kind, status, suggestedQueries
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        label = try c.decode(String.self, forKey: .label)
        kind = try c.decode(VerificationTargetKind.self, forKey: .kind)
        status = try c.decodeIfPresent(VerificationOutcome.self, forKey: .status) ?? .pending
        suggestedQueries = try c.decodeIfPresent([String].self, forKey: .suggestedQueries) ?? []
    }

    /// Rendered label, e.g. `《民法典》第577条 [待核]`.
    public var displayLabel: String { "\(label) \(status.tag)" }

    // MARK: - Immutable status transitions

    public func markedVerified() -> VerificationTarget {
        var copy = self
        copy.status = .verified
        return copy
    }

    public func markedRejected() -> VerificationTarget {
        var copy = self
        copy.status = .rejected
        return copy
    }

    // MARK: - Bridge to the canonical anchor (no fork)

    public func toAnchor() -> VerificationAnchor {
        VerificationAnchor(
            id: id,
            label: label,
            kind: kind.anchorKind,
            status: anchorStatus,
            query: suggestedQueries.first ?? label,
            preferredSources: []
        )
    }

    private var anchorStatus: VerificationStatus {
        switch status {
        case .pending: return .pending
        case .rejected: return .rejected
        case .verified:
            switch kind {
            case .statute, .monetaryRule, .date: return .verifiedLaw
            case .caseLaw: return .verifiedCase
            case .article, .doctrinalClaim: return .scholarlyReference
            }
        }
    }
}
