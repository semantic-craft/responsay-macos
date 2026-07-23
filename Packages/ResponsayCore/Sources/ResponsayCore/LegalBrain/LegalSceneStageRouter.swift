import Foundation

// MARK: - 104 LegalSceneStageRouter
//
// A routing policy on top of the deterministic signal layer (113–117). It does
// NOT re-derive scoring rules: it consumes the assembled `ContextSignalBundle`,
// asks the built `ContextConfidenceScorer` (117) for a `SceneStageClassification`,
// then maps confidence → which surface to show and pulls the matching candidate
// cards from the registry (102). No model call — candidate cards must never wait
// on an LLM (spec §6/§7; ADR-0008/0012 downgrade铁律: low confidence → ask,
// never auto-run a model).

/// Which surface the capsule should present for a legal trigger.
public enum LegalRouteDecision: Sendable {
    /// High confidence (≥ `autoThreshold`, scorer not asking): show candidates now.
    case autoCandidates(SceneStageClassification, candidates: [LegalCandidateCard])
    /// Mid confidence (`confirmThreshold ..< autoThreshold`): a best-guess scene with
    /// a confirm/switch affordance; the would-run candidates ride behind it.
    case confirmScene(SceneStageClassification, candidates: [LegalCandidateCard])
    /// Low confidence (< `confirmThreshold`) but text IS selected: generic legal actions.
    case genericLegalActions(SceneStageClassification, actions: [LegalCandidateCard])
    /// No usable selection: ask the user to select text first (cannot route on nothing).
    case needsSelection(SceneStageClassification)
}

public extension LegalRouteDecision {
    /// The underlying classification, regardless of tier.
    var classification: SceneStageClassification {
        switch self {
        case let .autoCandidates(c, _), let .confirmScene(c, _),
             let .genericLegalActions(c, _), let .needsSelection(c):
            return c
        }
    }

    /// The cards on offer (empty for `.needsSelection`).
    var cards: [LegalCandidateCard] {
        switch self {
        case let .autoCandidates(_, cs), let .confirmScene(_, cs), let .genericLegalActions(_, cs):
            return cs
        case .needsSelection:
            return []
        }
    }

    /// Stable tier name for logging / tests.
    var tier: String {
        switch self {
        case .autoCandidates:      return "auto"
        case .confirmScene:        return "confirm"
        case .genericLegalActions: return "generic"
        case .needsSelection:      return "needsSelection"
        }
    }
}

public struct LegalSceneStageRouter: Sendable {
    /// ≥ this confidence (and scorer not asking) → show candidates without confirmation.
    /// Note: the scorer's own ask cutoff (117) is 0.55; the router's confirm band runs
    /// up to 0.65, so 0.55–0.65 still gets a soft confirm card rather than auto-running.
    public static let autoThreshold = 0.65
    /// ≥ this (and < `autoThreshold`) → scene-confirm card; below → generic actions.
    public static let confirmThreshold = 0.45

    private let scorer: ContextConfidenceScorer

    public init(scorer: ContextConfidenceScorer = ContextConfidenceScorer()) {
        self.scorer = scorer
    }

    /// Route an assembled signal bundle into a surface decision + candidate cards.
    public func route(_ bundle: ContextSignalBundle, registry: LegalSkillRegistry) -> LegalRouteDecision {
        let classification = scorer.classify(
            appProfile: bundle.appProfile,
            headingSignals: bundle.headingSignals,
            urlSignal: bundle.urlSignal,
            hasSelection: bundle.hasSelection
        )

        // Can't route a legal action without text to act on.
        guard bundle.hasSelection else { return .needsSelection(classification) }

        // Candidate cards for the winning scene/stage; heading cues narrow by keyword.
        let keywords = bundle.headingSignals.map(\.normalized)
        let stage = classification.stage == .unknown ? nil : classification.stage
        let skills = registry.candidates(scene: classification.scene, stage: stage, keywords: keywords)
        let candidates = skills.map {
            Self.card(from: $0, routingStage: classification.stage, confidence: classification.confidence)
        }

        let confidence = classification.confidence
        if confidence >= Self.autoThreshold, !classification.shouldAskUser, !candidates.isEmpty {
            return .autoCandidates(classification, candidates: candidates)
        }
        if confidence >= Self.confirmThreshold, !candidates.isEmpty {
            return .confirmScene(classification, candidates: candidates)
        }

        // Low confidence — or a confident scene with no authored skill yet — falls back
        // to generic legal actions so the user is never left with an empty surface.
        let routed = (candidates.isEmpty && confidence >= Self.confirmThreshold)
            ? Self.annotate(classification, "该场景暂无内置技能 → 通用法律动作")
            : classification
        return .genericLegalActions(routed, actions: Self.genericActions(for: routed))
    }

    // MARK: - Card building

    /// Build a candidate card for a skill. `routingStage` is the router's best-guess
    /// stage (used only to resolve which of the skill's applicable stages to show);
    /// the card's `scene` always reflects the skill's own declared scene. Reused by
    /// `LegalSkillRuntime` (105) so palette + auto-candidate cards stay identical.
    static func card(
        from skill: LegalSkillCompiled,
        routingStage: LegalStage,
        confidence: Double
    ) -> LegalCandidateCard {
        let meta = skill.metadata
        let stages = meta.sceneLayer.applicableStages
        let stage = stages.contains(routingStage)
            ? routingStage
            : (stages.first ?? routingStage)
        return LegalCandidateCard(
            id: skill.id,
            skillId: skill.id,
            title: meta.title,
            subtitle: meta.reasoningKernel.mandatoryMapping.first ?? "",
            scene: meta.sceneLayer.scene,
            stage: stage,
            confidence: confidence,
            badges: badges(scene: meta.sceneLayer.scene, risk: meta.risk.level),
            requiredInputs: meta.inputs,
            preview: nil,
            action: .executeSkill(skillId: skill.id)
        )
    }

    /// The four generic legal actions (spec §9): runnable without a specific skill.
    /// The `generic.*` skillId namespace is resolved by the executor (106) to built-in
    /// fallback prompts, so these stay forward-compatible with `.executeSkill`.
    static func genericActions(for c: SceneStageClassification) -> [LegalCandidateCard] {
        let specs: [(id: String, title: String)] = [
            ("generic.elementAnalysis", "要件分析"),
            ("generic.factVerification", "待核事实"),
            ("generic.searchQuery", "检索式"),
            ("generic.counterargument", "反方观点"),
        ]
        return specs.map { spec in
            LegalCandidateCard(
                id: spec.id,
                skillId: spec.id,
                title: spec.title,
                subtitle: "通用法律动作 · 不依赖具体技能",
                scene: c.scene,
                stage: c.stage,
                confidence: c.confidence,
                badges: ["通用", "待核"],
                requiredInputs: [.selectedText],
                preview: nil,
                action: .executeSkill(skillId: spec.id)
            )
        }
    }

    static func badges(scene: LegalScene, risk: LegalSkillRiskLevel) -> [String] {
        var badges = [sceneLabel(scene)]
        if risk == .high { badges.append("高风险") }
        badges.append("待核")
        return badges
    }

    static func sceneLabel(_ scene: LegalScene) -> String {
        switch scene {
        case .litigation:        return "诉讼"
        case .academicWriting:   return "学术"
        case .privacy:           return "隐私"
        case .contract:          return "合同"
        case .productCompliance: return "合规"
        case .unknown:           return "通用"
        }
    }

    private static func annotate(_ c: SceneStageClassification, _ reason: String) -> SceneStageClassification {
        SceneStageClassification(
            scene: c.scene, stage: c.stage, confidence: c.confidence,
            reasons: c.reasons + [reason], shouldAskUser: c.shouldAskUser
        )
    }
}
