import Foundation

/// The review card the Capsule shows, derived from the capture state's fields by one pure
/// function (#3 deepening) — replacing the optional cascade that `ReviewCardView` used to infer
/// inline. The previously-blank "review with no content" is now an explicit `.empty`, so a
/// review entered before its content is set renders nothing instead of a broken coach card.
public enum CaptureReviewState: Sendable {
    /// The legal send-preview gate (110) before a cloud call — top precedence, in front of all else.
    case legalConfirm(LegalPrivacyDecision)
    /// A run-skill's structured output (107) takes over the panel; the model route rides along.
    case legalResult(LegalSkillResponse, route: ModelRoute?)
    /// The coach review card: the user's original → idiomatic English + why + diff.
    case coach(ExpressionResult)
    /// Intent-aware terminal states are routed explicitly now; full interactive cards belong to #559.
    case intentNeedsReview(IntentReviewReason)
    case intentSafeUnavailable(IntentUnavailableReason)
    /// No card content yet — render nothing (was: a silently-blank coach card).
    case empty

    /// A payload-free discriminant, for routing and tests (the payloads aren't all Equatable).
    public enum Kind: Sendable, Equatable {
        case legalConfirm, legalResult, coach, intentNeedsReview, intentSafeUnavailable, empty
    }

    public var kind: Kind {
        switch self {
        case .legalConfirm: return .legalConfirm
        case .legalResult: return .legalResult
        case .coach: return .coach
        case .intentNeedsReview: return .intentNeedsReview
        case .intentSafeUnavailable: return .intentSafeUnavailable
        case .empty: return .empty
        }
    }

    /// Resolve the review card from the capture state's fields, in the precedence the old
    /// `ReviewCardView` cascade used: send-confirm → run-skill result → coach, then the
    /// explicit `.empty` (which was a silently-blank coach card before this seam).
    public static func resolve(
        legalSendConfirm: LegalPrivacyDecision?,
        legalResponse: LegalSkillResponse?,
        legalResponseRoute: ModelRoute?,
        result: ExpressionResult?,
        intentCaptureState: IntentCaptureState? = nil
    ) -> CaptureReviewState {
        if let legalSendConfirm { return .legalConfirm(legalSendConfirm) }
        if let legalResponse { return .legalResult(legalResponse, route: legalResponseRoute) }
        if let intentCaptureState {
            switch intentCaptureState {
            case let .needsReview(reason): return .intentNeedsReview(reason)
            case let .safeUnavailable(reason): return .intentSafeUnavailable(reason)
            }
        }
        if let result { return .coach(result) }
        return .empty
    }
}
