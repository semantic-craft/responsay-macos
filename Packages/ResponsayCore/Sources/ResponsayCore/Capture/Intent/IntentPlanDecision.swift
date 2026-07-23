import Foundation

public enum IntentPlanDecision: String, Codable, Sendable {
    case render
    case noIntentControl
    case needsReview
}
