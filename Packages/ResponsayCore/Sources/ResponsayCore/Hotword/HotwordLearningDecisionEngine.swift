import Foundation

/// Routes each correction-derived candidate to the four-tier auto-learn model (PRD 2026-06-19 §3).
/// Specialization (not just confidence) decides whether we interrupt the user: only specialized
/// terms ever toast or wait for confirmation; ordinary terms learn silently or stay clues.
public struct HotwordLearningDecisionEngine: Sendable {
    /// The high-confidence band floor (≥ this = high). Exposed so the #466 vocabulary tier reuses
    /// the same threshold instead of duplicating the magic number.
    public static let defaultHighConfidenceThreshold: Double = 0.85
    public static let defaultMidConfidenceThreshold: Double = 0.60

    private let highConfidenceThreshold: Double
    private let midConfidenceThreshold: Double
    private let classifier: HotwordSensitivityClassifier

    public init(
        highConfidenceThreshold: Double = HotwordLearningDecisionEngine.defaultHighConfidenceThreshold,
        midConfidenceThreshold: Double = HotwordLearningDecisionEngine.defaultMidConfidenceThreshold,
        classifier: HotwordSensitivityClassifier = HotwordSensitivityClassifier()
    ) {
        self.highConfidenceThreshold = highConfidenceThreshold
        self.midConfidenceThreshold = midConfidenceThreshold
        self.classifier = classifier
    }

    public func decide(
        proposals: [HotwordCandidateProposal],
        policy: HotwordConfirmationPolicy,
        existingManualTerms: Set<String>,
        existingAutoTerms: Set<String>,
        recentlyUndoneTerms: Set<String> = []
    ) -> [HotwordLearningDecision] {
        proposals.map { proposal in
            let explicitCorrection = isExplicitCorrection(proposal)
            if existingManualTerms.contains(proposal.term) {
                return explicitCorrection ? .add(proposal, notify: false) : .ignore(proposal, reason: "手动词已存在")
            }
            if existingAutoTerms.contains(proposal.term) {
                return explicitCorrection ? .add(proposal, notify: false) : .ignore(proposal, reason: "自动词已存在")
            }
            // 445 — tombstone: don't re-add a term the user just undid, unless the user
            // explicitly corrects this exact term again. That new edit is the fresh signal.
            if recentlyUndoneTerms.contains(proposal.term), !explicitCorrection {
                return .ignore(proposal, reason: "已撤销")
            }

            let specialized = classifier.isSpecialized(proposal.term)
            let band = self.band(for: proposal.confidence)

            let decision: HotwordLearningDecision
            switch (band, specialized) {
            case (.high, let isSpecialized):
                // Tier 1 specialized → add + toast; Tier 2 ordinary → add silently.
                decision = .add(proposal, notify: isSpecialized)
            case (.mid, true), (.low, true):
                // Tier 4 — specialized but uncertain: hold for confirmation, never auto-apply.
                decision = .confirm(proposal)
            case (.mid, false):
                // Tier 3 — an ordinary word the user deliberately corrected (e.g. cloud→Claude):
                // not distinctive enough to auto-apply, but a real edit, so hold it for the user to
                // confirm in the audit panel rather than dropping it silently.
                decision = .confirm(proposal)
            case (.low, false):
                decision = .ignore(proposal, reason: "置信度过低")
            }

            // Policy override: 每次确认 turns any auto-add into a pending confirm.
            if policy == .confirmEveryTime, case .add = decision {
                return .confirm(proposal)
            }
            return decision
        }
    }

    private enum Band { case high, mid, low }

    private func band(for confidence: Double) -> Band {
        if confidence >= highConfidenceThreshold { return .high }
        if confidence >= midConfidenceThreshold { return .mid }
        return .low
    }

    private func isExplicitCorrection(_ proposal: HotwordCandidateProposal) -> Bool {
        guard let source = proposal.sourceTerm?.trimmingCharacters(in: .whitespacesAndNewlines),
              !source.isEmpty else { return false }
        return source != proposal.term
    }
}
