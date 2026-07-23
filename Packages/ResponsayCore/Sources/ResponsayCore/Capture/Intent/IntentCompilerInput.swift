import Foundation

public struct IntentCompilerInput: Sendable, Equatable {
    public let finalTranscript: String
    public let locale: CaptureLocale
    public let allowedContext: ExpressionContext?
    public let routePolicy: IntentRoutePolicy
    public let sourceUnits: [IntentSourceUnit]
    /// The app-built whitelist entity table (#562) the compiler may select from by ID.
    public let entityCandidates: [IntentEntityCandidate]

    public init(
        finalTranscript: String,
        locale: CaptureLocale,
        allowedContext: ExpressionContext?,
        routePolicy: IntentRoutePolicy,
        sourceUnits: [IntentSourceUnit],
        entityCandidates: [IntentEntityCandidate] = []
    ) {
        self.finalTranscript = finalTranscript
        self.locale = locale
        self.allowedContext = allowedContext
        self.routePolicy = routePolicy
        self.sourceUnits = sourceUnits
        self.entityCandidates = entityCandidates
    }

    public static func == (lhs: IntentCompilerInput, rhs: IntentCompilerInput) -> Bool {
        lhs.finalTranscript == rhs.finalTranscript
            && lhs.locale.rawValue == rhs.locale.rawValue
            && lhs.allowedContext == rhs.allowedContext
            && lhs.routePolicy == rhs.routePolicy
            && lhs.sourceUnits == rhs.sourceUnits
            && lhs.entityCandidates == rhs.entityCandidates
    }
}
