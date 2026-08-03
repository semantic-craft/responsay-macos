import Foundation
import ResponsayCore

@MainActor
struct AutoLearnHotwordProcessor {
    typealias Extract = (HotwordCorrectionContext) async -> HotwordCandidateExtractionResult
    typealias AddAuto = (HotwordCandidateProposal) -> Bool
    typealias Record = (HotwordCandidateProposal, HotwordLearningRecordStatus) -> Bool

    private let isEnabled: () -> Bool
    private let isExplicitCorrectionLearningEnabled: () -> Bool
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
        isExplicitCorrectionLearningEnabled: @escaping () -> Bool = { false },
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
        self.isExplicitCorrectionLearningEnabled = isExplicitCorrectionLearningEnabled
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
            isExplicitCorrectionLearningEnabled: { ExplicitCorrectionLearningSettings.isEnabled },
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
        let explicit = processExplicitCorrectionSynchronously(context)
        guard isEnabled() else { return explicit }
        let broad = await processBroadLearning(context, excludingTerms: Set(explicit.addedTerms))
        return AutoLearnHotwordProcessResult(
            addedTerms: explicit.addedTerms + broad.addedTerms,
            notifiedTerms: explicit.notifiedTerms + broad.notifiedTerms,
            extractionStatus: broad.extractionStatus)
    }

    /// Direct user supervision is resolved synchronously so the next capture's Qwen
    /// `vocabulary` and Context snapshot can include the correction immediately.
    @MainActor
    func processExplicitCorrectionSynchronously(
        _ context: HotwordCorrectionContext
    ) -> AutoLearnHotwordProcessResult {
        guard isExplicitCorrectionLearningEnabled() else {
            return AutoLearnHotwordProcessResult(addedTerms: [], extractionStatus: .notConfigured)
        }
        guard longTermLearningRejection(context) == nil else {
            return AutoLearnHotwordProcessResult(addedTerms: [], extractionStatus: .notConfigured)
        }

        let candidates = RuleBasedHotwordCandidateExtractor()
            .extractSynchronously(context)
            .filter { proposal in
                guard let source = proposal.sourceTerm?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                    return false
                }
                return !source.isEmpty
                    && source != proposal.term
                    && proposal.confidence >= HotwordLearningDecisionEngine.defaultMidConfidenceThreshold
            }
        return apply(
            candidates,
            to: context,
            extractionStatus: candidates.isEmpty ? .lowConfidence : .ready,
            autoAddExplicitCorrections: true)
    }

    @MainActor
    func processBroadLearning(
        _ context: HotwordCorrectionContext,
        excludingTerms: Set<String> = []
    ) async -> AutoLearnHotwordProcessResult {
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
        return apply(
            extraction.candidates.filter { !excludingTerms.contains($0.term) },
            to: context,
            extractionStatus: extraction.status,
            autoAddExplicitCorrections: false)
    }

    @MainActor
    private func apply(
        _ proposals: [HotwordCandidateProposal],
        to context: HotwordCorrectionContext,
        extractionStatus: HotwordCandidateExtractionStatus,
        autoAddExplicitCorrections: Bool
    ) -> AutoLearnHotwordProcessResult {
        let candidates = proposals.map {
            $0.withContext(appName: context.appName, windowTitle: context.windowTitle)
        }
        let decisions = decisionEngine.decide(
            proposals: candidates,
            policy: confirmationPolicy(),
            existingManualTerms: existingManualTerms(),
            existingAutoTerms: existingAutoTerms(),
            recentlyUndoneTerms: recentlyUndoneTerms(),
            autoAddExplicitCorrections: autoAddExplicitCorrections)

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
            addedTerms: addedTerms, notifiedTerms: notifiedTerms, extractionStatus: extractionStatus)
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
        let candidates = RuleBasedHotwordCandidateExtractor().extractSynchronously(context)
        return HotwordCandidateExtractionResult(
            candidates: candidates,
            status: candidates.isEmpty ? .lowConfidence : .ready)
    }
}
