import Foundation
import ResponsayCore

/// Runs a legal skill on the BYOK cloud provider direct (243 / 245, epic 238) — app-direct only,
/// the Node LLM routes are retired. No model configured → a clear error. `.blocked` (security-gate
/// denial, e.g. a password field) is the only route that suppresses search verification; there is
/// no local-model route. Conforms to `LegalSkillExecutorAPI`, so `LegalSkillRuntime` needs no change.
struct RoutingLegalSkillExecutor: LegalSkillExecutorAPI {
    init() {}

    // 技能平台 lane 统一走 `resolveSkill`（含技能 JSON 修复：repair 请求由同一 executor 实例
    // 发出，天然沿用技能模型，不会回退到听写模型）；听写/问答 lane 不受影响。
    func executeSkill(_ request: LegalSkillExecutionRequest) async throws -> LegalSkillExecutionResponse {
        Diag.llm(.info, "executeSkill start", fields: ["skill": request.skillId])
        do {
            guard let endpoint = LLMEndpointResolver.resolveSkill() else { throw LLMEndpointResolver.notConfigured }
            let result = try await DirectLegalSkillExecutorAPI(endpoint: endpoint).executeSkill(request)
            Diag.llm(.info, "executeSkill done", fields: ["skill": request.skillId, "model": endpoint.model])
            return result
        } catch {
            Diag.llm(.error, "executeSkill failed", fields: ["skill": request.skillId], error: error.localizedDescription)
            throw error
        }
    }

    func supportsSearchVerification(route: ModelRoute) -> Bool {
        guard route != .blocked, let endpoint = LLMEndpointResolver.resolveSkill() else { return false }
        return DirectLegalSkillExecutorAPI(endpoint: endpoint, searchBackend: searchBackend())
            .supportsSearchVerification(route: route)
    }

    func searchVerification(_ anchor: VerificationAnchor, route: ModelRoute) async throws -> VerifiedSource? {
        guard route != .blocked, let endpoint = LLMEndpointResolver.resolveSkill() else {
            throw LegalSkillRuntimeError.executorNotImplemented(skillId: "legal.verification.search")
        }
        return try await DirectLegalSkillExecutorAPI(endpoint: endpoint, searchBackend: searchBackend())
            .searchVerification(anchor, route: route)
    }

    /// 488 找类案。此前缺这层转发，落到协议默认实现直接抛「未实现」——app-direct 下 找类案
    /// 永远失败；补上后与其余技能搜索一致走技能平台模型。
    func searchCaseCandidates(_ query: String, route: ModelRoute) async throws -> [CaseCandidate] {
        guard route != .blocked, let endpoint = LLMEndpointResolver.resolveSkill() else {
            throw LegalSkillRuntimeError.executorNotImplemented(skillId: "legal.case.search")
        }
        return try await DirectLegalSkillExecutorAPI(endpoint: endpoint, searchBackend: searchBackend())
            .searchCaseCandidates(query, route: route)
    }

    /// 用户配的独立检索服务(豆包搜索 / Perplexity)。[待核] 核验跟着这一个开关走
    /// ——不看「任意提问」的联网开关:那个开关管的是提问要不要联网,与法律核验是两回事。
    private func searchBackend() -> (any WebSearchBackend)? {
        WebSearchProviderSettings.backend()
    }
}
