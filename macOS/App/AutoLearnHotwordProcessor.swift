import Foundation
import ResponsayCore

@MainActor
struct AutoLearnHotwordProcessor {
    typealias Extract = (HotwordCorrectionContext) async -> HotwordCandidateExtractionResult
    typealias AddAuto = (HotwordCandidateProposal) -> Bool
    typealias Record = (HotwordCandidateProposal, HotwordLearningRecordStatus) -> Bool

    private let isEnabled: () -> Bool
    private let mode: () -> AutoLearnHotwordMode
    private let confirmationPolicy: () -> HotwordConfirmationPolicy
    private let existingManualTerms: () -> Set<String>
    private let existingAutoTerms: () -> Set<String>
    private let addAuto: AddAuto
    private let record: Record
    private let localModelExtract: Extract?
    private let longTermLearningRejection: (HotwordCorrectionContext) -> LexicalProfilePrivacyRejectionReason?
    private let recentlyUndoneTerms: () -> Set<String>
    private let decisionEngine = HotwordLearningDecisionEngine()

    init(
        isEnabled: @escaping () -> Bool,
        mode: @escaping () -> AutoLearnHotwordMode,
        confirmationPolicy: @escaping () -> HotwordConfirmationPolicy,
        existingManualTerms: @escaping () -> Set<String>,
        existingAutoTerms: @escaping () -> Set<String>,
        addAuto: @escaping AddAuto,
        record: @escaping Record,
        localModelExtract: Extract? = nil,
        longTermLearningRejection: @escaping (HotwordCorrectionContext) -> LexicalProfilePrivacyRejectionReason? = { _ in nil },
        recentlyUndoneTerms: @escaping () -> Set<String> = { [] }
    ) {
        self.isEnabled = isEnabled
        self.mode = mode
        self.confirmationPolicy = confirmationPolicy
        self.existingManualTerms = existingManualTerms
        self.existingAutoTerms = existingAutoTerms
        self.addAuto = addAuto
        self.record = record
        self.localModelExtract = localModelExtract
        self.longTermLearningRejection = longTermLearningRejection
        self.recentlyUndoneTerms = recentlyUndoneTerms
    }

    static func live() -> AutoLearnHotwordProcessor {
        AutoLearnHotwordProcessor(
            isEnabled: { AutoLearnHotwordSettings.isEnabled },
            mode: { AutoLearnHotwordModeSettings.mode() },
            confirmationPolicy: { AutoLearnHotwordHistorySettings.confirmationPolicy() },
            existingManualTerms: { Set(ContextHotwordSettings.hotwords()) },
            existingAutoTerms: { Set(ContextHotwordSettings.autoHotwords()) },
            addAuto: { proposal in
                ContextHotwordSettings.addAuto(
                    proposal.term,
                    source: proposal.source,
                    reason: proposal.reason,
                    confidence: proposal.confidence,
                    appName: proposal.appName)
            },
            record: { proposal, status in
                AutoLearnHotwordHistorySettings.append(proposal, status: status)
            },
            localModelExtract: { context in
                guard let endpoint = LLMEndpointResolver.resolveText(), endpoint.isLocal else {
                    return HotwordCandidateExtractionResult(candidates: [], status: .notConfigured)
                }
                return await DirectHotwordLLMCandidateExtractor(
                    endpoint: endpoint,
                    source: .localModel).extractWithStatus(context)
            },
            longTermLearningRejection: { context in
                LexicalProfilePrivacyGate().rejectionReason(
                    texts: [context.insertedText, context.userFinalText],
                    appName: context.appName,
                    windowTitle: context.windowTitle)
            },
            recentlyUndoneTerms: {
                HotwordLearningHistory(records: AutoLearnHotwordHistorySettings.records())
                    .tombstonedTerms()
            })
    }

    @MainActor
    func process(_ context: HotwordCorrectionContext) async -> AutoLearnHotwordProcessResult {
        guard isEnabled() else {
            return AutoLearnHotwordProcessResult(addedTerms: [], extractionStatus: .notConfigured)
        }
        guard longTermLearningRejection(context) == nil else {
            return AutoLearnHotwordProcessResult(addedTerms: [], extractionStatus: .notConfigured)
        }

        let extraction = await extract(context)
        guard !extraction.candidates.isEmpty else {
            return AutoLearnHotwordProcessResult(addedTerms: [], extractionStatus: extraction.status)
        }

        let candidates = extraction.candidates.map {
            $0.withContext(appName: context.appName, windowTitle: context.windowTitle)
        }
        let decisions = decisionEngine.decide(
            proposals: candidates,
            policy: confirmationPolicy(),
            existingManualTerms: existingManualTerms(),
            existingAutoTerms: existingAutoTerms(),
            recentlyUndoneTerms: recentlyUndoneTerms())

        var addedTerms: [String] = []
        var notifiedTerms: [String] = []
        for decision in decisions {
            switch decision {
            case let .add(proposal, notify):
                guard record(proposal, .added) else { continue }
                if addAuto(proposal) {
                    addedTerms.append(proposal.term)
                    // Only specialized terms toast; ordinary terms learn silently (PRD §3 Tier 1/2).
                    if notify { notifiedTerms.append(proposal.term) }
                } else {
                    _ = record(proposal, .ignored)
                }
            case let .confirm(proposal):
                _ = record(proposal, .pending)
            case let .ignore(proposal, _):
                _ = record(proposal, .ignored)
            }
        }

        return AutoLearnHotwordProcessResult(
            addedTerms: addedTerms, notifiedTerms: notifiedTerms, extractionStatus: extraction.status)
    }

    @MainActor
    private func extract(_ context: HotwordCorrectionContext) async -> HotwordCandidateExtractionResult {
        switch mode() {
        case .localRules:
            return await localRuleExtraction(context)
        case .localModel:
            guard let localModelExtract else { return await localRuleExtraction(context) }
            let result = await localModelExtract(context)
            return result.candidates.isEmpty ? await localRuleExtraction(context) : result
        }
    }

    @MainActor
    private func localRuleExtraction(_ context: HotwordCorrectionContext) async -> HotwordCandidateExtractionResult {
        let candidates = (try? await RuleBasedHotwordCandidateExtractor().extract(context)) ?? []
        return HotwordCandidateExtractionResult(
            candidates: candidates,
            status: candidates.isEmpty ? .lowConfidence : .ready)
    }
}
