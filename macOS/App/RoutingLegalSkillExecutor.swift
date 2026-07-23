import Foundation
import ResponsayCore

/// Runs a legal skill on the BYOK cloud provider direct (243 / 245, epic 238) — app-direct only,
/// the Node LLM routes are retired. No model configured → a clear error. `.blocked` (security-gate
/// denial, e.g. a password field) is the only route that suppresses search verification; there is
/// no local-model route. Conforms to `LegalSkillExecutorAPI`, so `LegalSkillRuntime` needs no change.
struct RoutingLegalSkillExecutor: LegalSkillExecutorAPI {
    init() {}

    func executeSkill(_ request: LegalSkillExecutionRequest) async throws -> LegalSkillExecutionResponse {
        Diag.llm(.info, "executeSkill start", fields: ["skill": request.skillId])
        do {
            guard let endpoint = LLMEndpointResolver.resolveText() else { throw LLMEndpointResolver.notConfigured }
            let result = try await DirectLegalSkillExecutorAPI(endpoint: endpoint).executeSkill(request)
            Diag.llm(.info, "executeSkill done", fields: ["skill": request.skillId])
            return result
        } catch {
            Diag.llm(.error, "executeSkill failed", fields: ["skill": request.skillId], error: error.localizedDescription)
            throw error
        }
    }

    func supportsSearchVerification(route: ModelRoute) -> Bool {
        guard route != .blocked, let endpoint = LLMEndpointResolver.resolveText() else { return false }
        return SearchVerificationService.supportsSearch(
            providerId: endpoint.providerId, baseURLHost: endpoint.host)
    }

    func searchVerification(_ anchor: VerificationAnchor, route: ModelRoute) async throws -> VerifiedSource? {
        guard route != .blocked, let endpoint = LLMEndpointResolver.resolveText() else {
            throw LegalSkillRuntimeError.executorNotImplemented(skillId: "legal.verification.search")
        }
        return try await DirectLegalSkillExecutorAPI(endpoint: endpoint)
            .searchVerification(anchor, route: route)
    }
}
