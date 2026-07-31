import Foundation

/// App-direct legal-skill executor (243, epic 238). The legal prompt is already assembled
/// client-side (`LegalPromptAssembler`, 106) — the backend route was a pure passthrough — so
/// going direct only swaps the destination from our Node backend to the BYOK provider. Conforms
/// to the same `LegalSkillExecutorAPI`, so `LegalSkillRuntime` is unchanged.
///
/// Privacy (110): a `localOnly` route must never reach a cloud endpoint; this executor refuses
/// it (the app's routing layer also keeps `localOnly` on the local/backend path).
public struct DirectLegalSkillExecutorAPI: LegalSkillExecutorAPI {
    let endpoint: LLMEndpoint
    let client: LLMChatClient
    /// 独立检索服务(豆包搜索 / Perplexity)。配了就用它核验 [待核] ——检索 API 本身就返回
    /// 标题/URL/摘要,正是 `VerifiedSource` 要的,不必再让模型转述一遍;主模型不支持联网也能核。
    /// nil = 没配 → 走下面「模型自带联网」的三条老路。
    let searchBackend: (any WebSearchBackend)?
    /// Injectable so the core stays free of nondeterministic `UUID()` in tests; the app default
    /// supplies a real id (the backend used to mint this).
    let runIdProvider: @Sendable () -> String

    public init(
        endpoint: LLMEndpoint,
        searchBackend: (any WebSearchBackend)? = nil,
        session: URLSession = .shared,
        runIdProvider: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.endpoint = endpoint
        self.searchBackend = searchBackend
        self.client = LLMChatClient(session: session)
        self.runIdProvider = runIdProvider
    }

    public func executeSkill(_ request: LegalSkillExecutionRequest) async throws -> LegalSkillExecutionResponse {
        guard !(request.modelRoute == .localOnly && !endpoint.isLocal) else {
            throw LLMError.notConfigured   // never leak a localOnly skill to cloud
        }
        let chat = try LLMChatRequestBuilder.makeRequest(
            endpoint: endpoint, system: request.systemPrompt, user: request.userPrompt, timeout: 90)
        let raw = try await client.execute(chat)
        return LegalSkillExecutionResponse(
            output: raw, runId: runIdProvider(), provider: endpoint.providerId, route: nil)
    }

    public func supportsSearchVerification(route: ModelRoute) -> Bool {
        guard route != .blocked, route != .localOnly, !endpoint.isLocal else { return false }
        return searchBackend != nil || modelCanSearch
    }

    /// 主模型自己能不能联网。和 `supportsSearchVerification` 分开:配了检索服务只解锁「核验」,
    /// 解锁不了「类案检索」——后者要模型联网搜完再输出结构化候选,纯检索 API 给不了。
    private var modelCanSearch: Bool {
        SearchVerificationService.supportsSearch(
            providerId: endpoint.providerId, baseURLHost: endpoint.host)
    }

    public func searchCaseCandidates(_ query: String, route: ModelRoute) async throws -> [CaseCandidate] {
        guard route != .blocked, route != .localOnly, !endpoint.isLocal, modelCanSearch else {
            throw LegalSkillRuntimeError.executorNotImplemented(skillId: "legal.case.search")
        }
        // The model returns candidates; the screener (#473/474) gates them — so an honest
        // "未找到→[]" is the right failure, never a fabricated case.
        let system = "你是法律检索助手。用联网搜索找真实存在的类案，只输出 JSON，绝不编造案例或案号；没有就返回空。"
        let user = CaseCandidateSearchParser.prompt(query: query)
        let chat = try LLMChatRequestBuilder.makeRequest(
            endpoint: endpoint, system: system, user: user, searchEnabled: true, timeout: 90)
        let raw = try await client.execute(chat)
        return CaseCandidateSearchParser.parse(raw)
    }

    public func searchVerification(_ anchor: VerificationAnchor, route: ModelRoute) async throws -> VerifiedSource? {
        guard supportsSearchVerification(route: route) else {
            throw LegalSkillRuntimeError.executorNotImplemented(skillId: "legal.verification.search")
        }
        // 配了独立检索服务就用它:一次检索直接拿到结构化来源,不必绕模型转述。
        if let searchBackend {
            return try await SearchVerificationService.verify(anchor, using: searchBackend)
        }
        let query = anchor.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? anchor.label
            : anchor.query
        let system = "你是法律引用核验助手。只核验来源是否存在，不替用户作最终法律判断。"
        let user = SearchVerificationService.buildVerificationPrompt(query: query, kind: anchor.kind)
        if ArkResponsesSearchRequestBuilder.supportsWebSearch(
            providerId: endpoint.providerId,
            baseURLHost: endpoint.host
        ) {
            let ark = try ArkResponsesSearchRequestBuilder.makeRequest(
                endpoint: endpoint,
                system: system,
                user: user,
                timeout: 90)
            let data = try await client.executeRaw(ark)
            guard let result = LLMSearchResultParser.parse(responseData: data, providerId: endpoint.providerId) else {
                return nil
            }
            return SearchVerificationService.toVerifiedSource(result)
        }
        let request = try LLMChatRequestBuilder.makeRequest(
            endpoint: endpoint,
            system: system,
            user: user,
            searchEnabled: true,
            timeout: 90)
        let data = try await client.executeRaw(request)
        guard let result = LLMSearchResultParser.parse(responseData: data, providerId: endpoint.providerId) else {
            return nil
        }
        return SearchVerificationService.toVerifiedSource(result)
    }
}
