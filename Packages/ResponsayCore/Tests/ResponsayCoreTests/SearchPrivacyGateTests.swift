import Testing
import Foundation
@testable import ResponsayCore

// MARK: - SearchPrivacyGate tests

@Suite("SearchPrivacyGate — privacy routing for LLM search")
struct SearchPrivacyGateTests {

    // MARK: - Search permission from ModelRoute

    @Test func localOnly_returnsDisabled() {
        let result = SearchPrivacyGate.permission(for: .localOnly)
        #expect(result == .disabled)
    }

    @Test func blocked_returnsDisabled() {
        let result = SearchPrivacyGate.permission(for: .blocked)
        #expect(result == .disabled)
    }

    @Test func cloudAllowed_returnsAllowed() {
        let result = SearchPrivacyGate.permission(for: .cloudAllowed)
        #expect(result == .allowed)
    }

    @Test func cloudRequiresConfirm_returnsNeedsConfirm() {
        let result = SearchPrivacyGate.permission(for: .cloudRequiresUserConfirm)
        #expect(result == .needsConfirm)
    }

    // MARK: - Computed properties

    @Test func isSearchEnabled_trueForAllowedAndNeedsConfirm() {
        #expect(SearchPrivacyGate.SearchPermission.allowed.isSearchEnabled)
        #expect(SearchPrivacyGate.SearchPermission.needsConfirm.isSearchEnabled)
    }

    @Test func isSearchEnabled_falseForDisabled() {
        #expect(!SearchPrivacyGate.SearchPermission.disabled.isSearchEnabled)
    }

    @Test func requiresConfirmation_trueOnlyForNeedsConfirm() {
        #expect(SearchPrivacyGate.SearchPermission.needsConfirm.requiresConfirmation)
        #expect(!SearchPrivacyGate.SearchPermission.allowed.requiresConfirmation)
        #expect(!SearchPrivacyGate.SearchPermission.disabled.requiresConfirmation)
    }

    // MARK: - Disabled reason

    @Test func disabledReason_localOnly() {
        let reason = SearchPrivacyGate.disabledReason(for: .localOnly)
        #expect(reason != nil)
        #expect(reason!.contains("本地"))
    }

    @Test func disabledReason_blocked() {
        let reason = SearchPrivacyGate.disabledReason(for: .blocked)
        #expect(reason != nil)
    }

    @Test func disabledReason_nilForCloud() {
        #expect(SearchPrivacyGate.disabledReason(for: .cloudAllowed) == nil)
        #expect(SearchPrivacyGate.disabledReason(for: .cloudRequiresUserConfirm) == nil)
    }

    // MARK: - Integration with LegalPrivacyDecision

    @Test func fromPrivacyDecision_localFirst() {
        let decision = LegalPrivacyDecision(
            route: .localOnly, sendFields: [], reasons: ["本地优先"])
        let permission = SearchPrivacyGate.permission(for: decision.route)
        #expect(permission == .disabled)
    }

    @Test func fromPrivacyDecision_cloudFirstNonSensitive() {
        let decision = LegalPrivacyDecision(
            route: .cloudAllowed, sendFields: [.selectedText, .sceneTag], reasons: [])
        let permission = SearchPrivacyGate.permission(for: decision.route)
        #expect(permission == .allowed)
    }

    @Test func fromPrivacyDecision_cloudFirstSensitive() {
        let decision = LegalPrivacyDecision(
            route: .cloudRequiresUserConfirm, sendFields: [.selectedText, .sceneTag],
            reasons: ["检测到敏感词"])
        let permission = SearchPrivacyGate.permission(for: decision.route)
        #expect(permission == .needsConfirm)
    }

    @Test func fromPrivacyDecision_askEachTime() {
        let decision = LegalPrivacyDecision(
            route: .cloudRequiresUserConfirm, sendFields: [.selectedText, .sceneTag],
            reasons: ["每次询问"])
        let permission = SearchPrivacyGate.permission(for: decision.route)
        #expect(permission == .needsConfirm)
    }
}
