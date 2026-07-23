import Testing
import Foundation
@testable import ResponsayCore

@Suite struct HotwordLearningDecisionTests {
    /// Deterministic engine: NER off + a one-term gazetteer, so "民法典" is the only specialized term
    /// and everything else is ordinary. Thresholds = the locked defaults (high 0.85 / mid 0.60).
    private let engine = HotwordLearningDecisionEngine(
        classifier: HotwordSensitivityClassifier(
            gazetteer: ["民法典"], useNamedEntityRecognition: false))

    private func proposal(_ term: String, _ confidence: Double) -> HotwordCandidateProposal {
        HotwordCandidateProposal(term: term, source: .localRules, confidence: confidence, reason: "用户纠正")
    }

    private func correction(_ sourceTerm: String, to term: String, confidence: Double) -> HotwordCandidateProposal {
        HotwordCandidateProposal(
            term: term,
            source: .localRules,
            confidence: confidence,
            reason: "用户纠正",
            sourceTerm: sourceTerm)
    }

    private func decide(_ p: HotwordCandidateProposal,
                        policy: HotwordConfirmationPolicy = .autoAddHighConfidence,
                        manual: Set<String> = [], auto: Set<String> = [],
                        undone: Set<String> = []) -> HotwordLearningDecision {
        engine.decide(proposals: [p], policy: policy,
                      existingManualTerms: manual, existingAutoTerms: auto,
                      recentlyUndoneTerms: undone)[0]
    }

    // MARK: - Tier 1 / Tier 2: high confidence adds; only specialized toasts

    @Test func ordinaryHighConfidenceAddsSilently() {
        let p = proposal("个人信息处理者", 0.86)
        #expect(decide(p) == .add(p, notify: false), "ordinary high-conf → added without a toast")
    }

    @Test func specializedHighConfidenceAddsWithToast() {
        let p = proposal("民法典", 0.86)
        #expect(decide(p) == .add(p, notify: true), "specialized high-conf → added + toast")
    }

    // MARK: - Tier 4: specialized but uncertain → pending

    @Test func specializedMidConfidenceWaitsForConfirmation() {
        #expect(decide(proposal("民法典", 0.70)) == .confirm(proposal("民法典", 0.70)))
    }

    @Test func specializedLowConfidenceWaitsForConfirmation() {
        #expect(decide(proposal("民法典", 0.40)) == .confirm(proposal("民法典", 0.40)))
    }

    // MARK: - Tier 3 / drop: ordinary uncertain is held for confirmation, low is dropped

    @Test func ordinaryMidConfidenceWaitsForConfirmation() {
        // A deliberately-corrected plain word (cloud→Claude lands here, 0.70) is held for the user
        // to confirm rather than dropped silently — never auto-applied.
        let p = proposal("文档草稿", 0.70)
        #expect(decide(p) == .confirm(p))
    }

    @Test func ordinaryLowConfidenceIsDropped() {
        let p = proposal("文档草稿", 0.40)
        #expect(decide(p) == .ignore(p, reason: "置信度过低"))
    }

    // MARK: - Policy override + guards

    @Test func confirmEveryTimeTurnsAddIntoPending() {
        let p = proposal("民法典", 0.97)
        #expect(decide(p, policy: .confirmEveryTime) == .confirm(p))
        let q = proposal("个人信息处理者", 0.97)
        #expect(decide(q, policy: .confirmEveryTime) == .confirm(q), "even silent adds become pending")
    }

    @Test func manualTermsWinOverAutoLearning() {
        let p = proposal("CLSCI", 0.99)
        #expect(decide(p, manual: ["CLSCI"]) == .ignore(p, reason: "手动词已存在"))
    }

    @Test func explicitCorrectionToExistingManualTermRecordsAliasSignal() {
        let p = correction("Cloud Code", to: "Claude Code", confidence: 0.86)
        #expect(decide(p, manual: ["Claude Code"]) == .add(p, notify: false))
    }

    @Test func existingAutoTermIsIgnored() {
        let p = proposal("CLSCI", 0.99)
        #expect(decide(p, auto: ["CLSCI"]) == .ignore(p, reason: "自动词已存在"))
    }

    @Test func explicitCorrectionToExistingAutoTermRecordsAliasSignal() {
        let p = correction("Cloud Code", to: "Claude Code", confidence: 0.86)
        #expect(decide(p, auto: ["Claude Code"]) == .add(p, notify: false))
    }

    @Test func recentlyUndoneTermIsIgnored() {
        let p = proposal("民法典", 0.9)
        #expect(decide(p, undone: ["民法典"]) == .ignore(p, reason: "已撤销"),
                "tombstone wins even over a specialized high-confidence term")
    }

    @Test func repeatedExplicitCorrectionCanRelearnUndoneTerm() {
        let p = correction("Cloud Xcode", to: "Claude Code", confidence: 0.86)
        #expect(decide(p, undone: ["Claude Code"]) == .add(p, notify: false),
                "a fresh user correction clears the old tombstone")
    }
}
