import Foundation

public struct DirectHotwordLLMCandidateExtractor: HotwordCandidateExtracting {
    private let endpoint: LLMEndpoint
    private let source: HotwordLearningSource
    private let minimumConfidence: Double
    private let executeRequest: @Sendable (URLRequest) async throws -> String

    public init(
        endpoint: LLMEndpoint,
        source: HotwordLearningSource,
        minimumConfidence: Double = 0.85,
        execute: @escaping @Sendable (URLRequest) async throws -> String
    ) {
        self.endpoint = endpoint
        self.source = source
        self.minimumConfidence = minimumConfidence
        self.executeRequest = execute
    }

    public init(
        endpoint: LLMEndpoint,
        source: HotwordLearningSource,
        minimumConfidence: Double = 0.85,
        session: URLSession = .shared
    ) {
        let client = LLMChatClient(session: session)
        self.init(endpoint: endpoint, source: source, minimumConfidence: minimumConfidence) { request in
            try await client.execute(request)
        }
    }

    public func extract(_ context: HotwordCorrectionContext) async throws -> [HotwordCandidateProposal] {
        await extractWithStatus(context).candidates
    }

    public func extractWithStatus(_ context: HotwordCorrectionContext) async -> HotwordCandidateExtractionResult {
        guard endpoint.isConfigured else {
            return HotwordCandidateExtractionResult(candidates: [], status: .notConfigured)
        }

        // Ground extraction in the actual edit: a wholesale rewrite (>1 changed region) or an edit
        // with no word substitution (pure append/deletion) is not a term correction — skip the LLM
        // call rather than letting it harvest entities from unchanged on-screen text.
        let delta = EditDelta.compute(inserted: context.insertedText, userFinal: context.userFinalText)
        guard !delta.substitutions.isEmpty, !delta.isLargeModify || delta.substitutions.count == 1 else {
            return HotwordCandidateExtractionResult(candidates: [], status: .lowConfidence)
        }

        do {
            let request = try HotwordLLMRequestBuilder.makeRequest(
                endpoint: endpoint, source: source, substitutions: delta.substitutions)
            let raw = try await executeRequest(request)
            guard let parsed = Self.parse(raw: raw, source: source, minimumConfidence: minimumConfidence) else {
                return HotwordCandidateExtractionResult(candidates: [], status: .malformedResponse)
            }
            let contextualized = parsed.map {
                $0.withContext(appName: context.appName, windowTitle: context.windowTitle)
            }
            guard !contextualized.isEmpty else {
                return HotwordCandidateExtractionResult(candidates: [], status: .lowConfidence)
            }
            return HotwordCandidateExtractionResult(candidates: contextualized, status: .ready)
        } catch HotwordCandidateExtractionError.timedOut {
            return HotwordCandidateExtractionResult(candidates: [], status: .timedOut)
        } catch let error as LLMError {
            return HotwordCandidateExtractionResult(candidates: [], status: .failed(error.localizedDescription))
        } catch {
            return HotwordCandidateExtractionResult(candidates: [], status: .failed(error.localizedDescription))
        }
    }

    private static func parse(
        raw: String,
        source: HotwordLearningSource,
        minimumConfidence: Double
    ) -> [HotwordCandidateProposal]? {
        guard let obj = LLMResponseParsing.jsonObject(from: raw),
              let candidates = obj["candidates"] as? [[String: Any]] else {
            return nil
        }

        return candidates.compactMap { item in
            guard let rawTerm = item["term"] as? String,
                  let confidence = item["confidence"] as? Double,
                  let reason = item["reason"] as? String else {
                return nil
            }
            let term = rawTerm.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty, confidence >= minimumConfidence else { return nil }
            return HotwordCandidateProposal(
                term: String(term.prefix(80)),
                source: source,
                confidence: confidence,
                reason: reason)
        }
    }
}
