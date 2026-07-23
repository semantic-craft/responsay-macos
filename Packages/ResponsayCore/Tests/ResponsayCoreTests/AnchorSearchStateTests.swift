import Testing
import Foundation
@testable import ResponsayCore

// MARK: - AnchorSearchState tests

@Suite("AnchorSearchState — verification UI state machine")
struct AnchorSearchStateTests {

    // MARK: - All cases constructible + Equatable

    @Test func allCases_areDistinct() {
        let source = VerifiedSource(
            title: "民法典", url: "https://flk.npc.gov.cn", accessedAt: "2026-06-11", provider: "kimi")
        let idle = AnchorSearchState.idle
        let loading = AnchorSearchState.loading
        let success = AnchorSearchState.success(source)
        let notFound = AnchorSearchState.notFound
        let err = AnchorSearchState.error("timeout")
        let disabled = AnchorSearchState.disabled

        #expect(idle != loading)
        #expect(success != notFound)
        #expect(err != disabled)
        #expect(idle == AnchorSearchState.idle)
    }

    // MARK: - from(source:) mapping

    @Test func fromSource_nonNil_returnsSuccess() {
        let source = VerifiedSource(
            title: "民法典第577条", url: "https://flk.npc.gov.cn/detail",
            accessedAt: "2026-06-11", provider: "kimi", snippet: "当事人一方不履行合同义务…")
        let state = AnchorSearchState.from(source: source)
        if case .success(let s) = state {
            #expect(s.title == "民法典第577条")
            #expect(s.provider == "kimi")
        } else {
            Issue.record("Expected .success, got \(state)")
        }
    }

    @Test func fromSource_nil_returnsNotFound() {
        let state = AnchorSearchState.from(source: nil)
        #expect(state == .notFound)
    }

    // MARK: - isPending

    @Test func isPending_trueForIdleAndLoading() {
        #expect(AnchorSearchState.idle.isPending)
        #expect(AnchorSearchState.loading.isPending)
    }

    @Test func isPending_falseForTerminalStates() {
        let source = VerifiedSource(
            title: "t", url: "u", accessedAt: "d", provider: "p")
        #expect(!AnchorSearchState.success(source).isPending)
        #expect(!AnchorSearchState.notFound.isPending)
        #expect(!AnchorSearchState.error("e").isPending)
        #expect(!AnchorSearchState.disabled.isPending)
    }

    // MARK: - hasResult

    @Test func hasResult_trueForSuccessAndNotFound() {
        let source = VerifiedSource(
            title: "t", url: "u", accessedAt: "d", provider: "p")
        #expect(AnchorSearchState.success(source).hasResult)
        #expect(AnchorSearchState.notFound.hasResult)
    }

    @Test func hasResult_falseForOtherStates() {
        #expect(!AnchorSearchState.idle.hasResult)
        #expect(!AnchorSearchState.loading.hasResult)
        #expect(!AnchorSearchState.error("e").hasResult)
        #expect(!AnchorSearchState.disabled.hasResult)
    }

    // MARK: - verifiedSource accessor

    @Test func verifiedSource_extractsFromSuccess() {
        let source = VerifiedSource(
            title: "判决书", url: "https://itslaw.com", accessedAt: "2026-06-11", provider: "qwen")
        let state = AnchorSearchState.success(source)
        #expect(state.verifiedSource?.title == "判决书")
    }

    @Test func verifiedSource_nilForOtherCases() {
        #expect(AnchorSearchState.idle.verifiedSource == nil)
        #expect(AnchorSearchState.loading.verifiedSource == nil)
        #expect(AnchorSearchState.notFound.verifiedSource == nil)
        #expect(AnchorSearchState.error("e").verifiedSource == nil)
        #expect(AnchorSearchState.disabled.verifiedSource == nil)
    }

    // MARK: - VerifiedSource Equatable conformance

    @Test func verifiedSource_equatable() {
        let a = VerifiedSource(title: "A", url: "u", accessedAt: "d", provider: "p", snippet: "s")
        let b = VerifiedSource(title: "A", url: "u", accessedAt: "d", provider: "p", snippet: "s")
        let c = VerifiedSource(title: "B", url: "u", accessedAt: "d", provider: "p", snippet: nil)
        #expect(a == b)
        #expect(a != c)
    }
}

// MARK: - AnchorVerifyCommit — discard stale/cancelled verify results

@Suite("AnchorVerifyCommit — cancellation guard")
struct AnchorVerifyCommitTests {
    private static let source = VerifiedSource(
        title: "民法典", url: "https://flk.npc.gov.cn", accessedAt: "2026-06-14", provider: "qwen")

    @Test func cancelled_discardsSuccess() {
        #expect(AnchorVerifyCommit.resolve(cancelled: true, result: .success(Self.source)) == nil)
    }

    @Test func cancelled_discardsError() {
        let err = LegalSkillRuntimeError.executorNotImplemented(skillId: "x")
        #expect(AnchorVerifyCommit.resolve(cancelled: true, result: .failure(err)) == nil)
    }

    @Test func live_success_commitsSuccess() {
        #expect(AnchorVerifyCommit.resolve(cancelled: false, result: .success(Self.source))
            == .success(Self.source))
    }

    @Test func live_nilSource_commitsNotFound() {
        #expect(AnchorVerifyCommit.resolve(cancelled: false, result: .success(nil)) == .notFound)
    }

    @Test func live_cancellationError_discards() {
        #expect(AnchorVerifyCommit.resolve(cancelled: false, result: .failure(CancellationError())) == nil)
    }

    @Test func live_realError_commitsError() {
        struct Boom: Error {}
        let state = AnchorVerifyCommit.resolve(cancelled: false, result: .failure(Boom()))
        if case .error = state { } else { Issue.record("expected .error, got \(String(describing: state))") }
    }
}
