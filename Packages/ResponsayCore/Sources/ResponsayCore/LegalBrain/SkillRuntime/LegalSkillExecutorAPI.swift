import Foundation

// MARK: - 106 LegalSkillExecutorAPI
//
// Separate from `CoachAPI` (which stays express/analyze). Production executor is
// `RoutingLegalSkillExecutor` (app-direct, ADR-0029: skills run on the BYOK cloud
// provider); the original backend `/legal/skill/execute` route and its
// `localhost:8787` config are retired. `searchVerification` is optional and
// app-direct: callers only expose it when the resolved provider supports web search.

public protocol LegalSkillExecutorAPI: Sendable {
    func executeSkill(_ request: LegalSkillExecutionRequest) async throws -> LegalSkillExecutionResponse
    /// Optional LLM-search source/fact verification for a pending anchor.
    func searchVerification(_ anchor: VerificationAnchor, route: ModelRoute) async throws -> VerifiedSource?
    func supportsSearchVerification(route: ModelRoute) -> Bool
    /// 488 — web-AI (qwenSearch) candidate cases for 找类案; gated by `supportsSearchVerification`.
    func searchCaseCandidates(_ query: String, route: ModelRoute) async throws -> [CaseCandidate]
}

public extension LegalSkillExecutorAPI {
    func searchVerification(_ anchor: VerificationAnchor, route: ModelRoute) async throws -> VerifiedSource? {
        throw LegalSkillRuntimeError.executorNotImplemented(skillId: "legal.verification.search")
    }

    func supportsSearchVerification(route: ModelRoute) -> Bool { false }

    func searchCaseCandidates(_ query: String, route: ModelRoute) async throws -> [CaseCandidate] {
        throw LegalSkillRuntimeError.executorNotImplemented(skillId: "legal.case.search")
    }
}
