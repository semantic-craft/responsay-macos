import Foundation

/// The *only* review data the capsule is allowed to render (#559 / spec decision 33): a minimal
/// sanitized draft and grounded candidates with short evidence labels. It deliberately carries
/// no `IntentPlan`, no source units, no raw side-note text, no provider response — those live
/// off-screen in `IntentReviewProposal` and never reach the view.
public struct IntentReviewContent: Sendable, Equatable {
    /// A safe partial draft the user may read, copy, or edit. `nil` when the compiler asked for
    /// review without a renderable draft (then the capsule offers copy-your-own-words instead).
    public let sanitizedDraft: String?
    /// Grounded alternatives the user may confirm. Empty for a generic "please confirm" review.
    public let candidates: [Candidate]

    public struct Candidate: Sendable, Equatable, Identifiable {
        public let id: String
        /// The grounded value shown to the user (e.g. a resolved name).
        public let value: String
        /// A short, content-free provenance label (e.g. "词典" / "光标上下文"). Never the raw
        /// clue speech or the internal plan.
        public let evidence: String

        public init(id: String, value: String, evidence: String) {
            self.id = id
            self.value = value
            self.evidence = evidence
        }
    }

    public init(sanitizedDraft: String?, candidates: [Candidate]) {
        self.sanitizedDraft = sanitizedDraft
        self.candidates = candidates
    }

    /// Whether there is anything to confirm or edit — a generic review with neither draft nor
    /// candidate only offers copy-your-words / retry / convert / cancel.
    public var isResolvable: Bool {
        sanitizedDraft?.isEmpty == false || !candidates.isEmpty
    }
}
