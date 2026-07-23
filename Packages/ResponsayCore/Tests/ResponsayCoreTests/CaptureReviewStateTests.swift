import Testing
@testable import ResponsayCore

/// #3 architecture deepening: the review card shown in the Capsule is derived by one pure, tested
/// function (`CaptureReviewState.resolve`) instead of the optional cascade inferred inside
/// `ReviewCardView`. The previously-blank "review with no content" becomes an explicit `.empty`.
/// Precedence matches the old cascade: legal send-confirm → run-skill result → coach.
/// (The standalone legal palette state was retired with 划词技能互动.)
struct CaptureReviewStateTests {
    private func expr() -> ExpressionResult { ExpressionResult(idiomatic: "Hi.", original: "hi", reasons: []) }
    private func response() -> LegalSkillResponse {
        LegalSkillResponse(runId: "r", skillId: "s", scene: .privacy, stage: .piaTriage,
                           summary: "", cards: [], verificationAnchors: [])
    }
    private func confirm() -> LegalPrivacyDecision {
        LegalPrivacyDecision(route: .cloudRequiresUserConfirm, sendFields: [], reasons: [])
    }

    @Test func noContent_resolvesToEmpty_notABlankCoachCard() {
        let state = CaptureReviewState.resolve(
            legalSendConfirm: nil, legalResponse: nil, legalResponseRoute: nil, result: nil)
        #expect(state.kind == .empty)
    }

    @Test func resultOnly_resolvesToCoach_carryingTheResult() {
        let r = expr()
        let state = CaptureReviewState.resolve(
            legalSendConfirm: nil, legalResponse: nil, legalResponseRoute: nil, result: r)
        #expect(state.kind == .coach)
        guard case .coach(let carried) = state else { Issue.record("expected .coach"); return }
        #expect(carried == r)
    }

    @Test func legalResult_winsOverCoach_andCarriesTheRoute() {
        // A run-skill result takes the panel over the coach card; the model route rides along.
        let state = CaptureReviewState.resolve(
            legalSendConfirm: nil, legalResponse: response(), legalResponseRoute: .cloudAllowed,
            result: expr())
        #expect(state.kind == .legalResult)
        guard case .legalResult(_, let route) = state else { Issue.record("expected .legalResult"); return }
        #expect(route == .cloudAllowed)
    }

    @Test func legalConfirm_winsOverEverything() {
        // The send-preview gate (110) is the top precedence — in front of all other cards.
        let state = CaptureReviewState.resolve(
            legalSendConfirm: confirm(), legalResponse: response(), legalResponseRoute: .cloudAllowed,
            result: expr())
        #expect(state.kind == .legalConfirm)
    }

    @Test func intentTerminalStatesRemainDistinct() {
        let review = CaptureReviewState.resolve(
            legalSendConfirm: nil,
            legalResponse: nil,
            legalResponseRoute: nil,
            result: nil,
            intentCaptureState: .needsReview(.compilerRequested))
        #expect(review.kind == .intentNeedsReview)

        let unavailable = CaptureReviewState.resolve(
            legalSendConfirm: nil,
            legalResponse: nil,
            legalResponseRoute: nil,
            result: nil,
            intentCaptureState: .safeUnavailable(.invalidPlan))
        #expect(unavailable.kind == .intentSafeUnavailable)
    }
}
