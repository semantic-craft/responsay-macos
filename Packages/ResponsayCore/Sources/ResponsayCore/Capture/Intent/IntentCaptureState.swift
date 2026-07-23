import Foundation

public enum IntentCaptureState: Sendable, Equatable {
    case needsReview(IntentReviewReason)
    case safeUnavailable(IntentUnavailableReason)
}
