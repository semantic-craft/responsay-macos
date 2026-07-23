import Foundation

/// Fuses the deterministic signals (app priors + heading boosts + URL boosts)
/// into the **built** `SceneStageClassification`, with a confidence + reason
/// trace and the honest downgrade ladder (issue 117). No LLM — candidate cards
/// must not wait on a model.
public struct ContextConfidenceScorer: Sendable {
    /// Below this confidence we ask the user to confirm the scene (v0.2 §4.7).
    public static let askThreshold = 0.55
    /// Saturation denominator: total signal weight at which confidence is undamped.
    static let saturationFloor = 0.6

    public init() {}

    public func classify(
        appProfile: AppContextProfile,
        headingSignals: [HeadingSignal],
        urlSignal: URLSignal?,
        hasSelection: Bool
    ) -> SceneStageClassification {
        // Downgrade铁律 (ADR-0008/0012): no selection → never pretend; ask / manual.
        guard hasSelection else {
            return SceneStageClassification(
                scene: .unknown, stage: .unknown, confidence: 0,
                reasons: ["无选中文本：请选中文本后触发，或手动选择场景"], shouldAskUser: true
            )
        }

        var scores: [LegalScene: Double] = [:]
        var reasons: [String] = []

        for prior in appProfile.legalScenePriors {
            scores[prior.scene, default: 0] += prior.weight
            reasons.append("应用 \(appProfile.appCategory.rawValue) → \(prior.scene.rawValue) (+\(prior.weight))")
        }
        if let urlSignal {
            for boost in urlSignal.legalSceneBoosts {
                scores[boost.scene, default: 0] += boost.weight
                reasons.append("网址 \(urlSignal.category.rawValue) → \(boost.scene.rawValue) (+\(boost.weight))")
            }
        }
        for signal in headingSignals {
            let scene = Self.scene(for: signal.stageHint)
            guard scene != .unknown else { continue }
            scores[scene, default: 0] += signal.confidenceBoost
            reasons.append("标题 \(signal.normalized) → \(scene.rawValue)/\(signal.stageHint.rawValue) (+\(signal.confidenceBoost))")
        }

        let total = scores.values.reduce(0, +)
        guard total > 0 else {
            return SceneStageClassification(
                scene: .unknown, stage: .unknown, confidence: 0,
                reasons: ["信号不足，需手动选择场景"], shouldAskUser: true
            )
        }

        let ranked = scores.sorted { $0.value > $1.value }
        let top = ranked[0]
        let second = ranked.count > 1 ? ranked[1].value : 0
        let margin = top.value / (top.value + second)              // dominance over runner-up
        let saturation = min(1.0, total / Self.saturationFloor)    // dampen weak total
        let confidence = margin * saturation

        // Stage: prefer a heading whose implied scene matches the winning scene.
        let stage = headingSignals.first { Self.scene(for: $0.stageHint) == top.key }?.stageHint
            ?? headingSignals.first?.stageHint
            ?? .unknown

        return SceneStageClassification(
            scene: top.key, stage: stage, confidence: confidence,
            reasons: reasons, shouldAskUser: confidence < Self.askThreshold
        )
    }

    /// Map a stage to the scene it most implies (for heading contributions).
    static func scene(for stage: LegalStage) -> LegalScene {
        switch stage {
        case .matterIntake, .claimChart, .evidenceReview, .briefDrafting, .argumentDrafting,
             .trialPreparation, .initialConsultation, .caseAssessment, .pleadingDrafting,
             .evidenceExchange, .postRetrievalSynthesis:
            return .litigation
        case .literatureReview, .citationDrafting, .searchPreparation, .peerReview:
            return .academicWriting
        case .productReview:
            return .productCompliance
        case .piaTriage:
            return .privacy
        case .unknown:
            return .unknown
        }
    }
}
