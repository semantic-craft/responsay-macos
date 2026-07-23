import Foundation

// MARK: - 105 LegalSkillRuntime
//
// The orchestrator the capture VM calls when the legal palette is triggered. It
// ties the deterministic layers together — assemble context (113–117) → route
// (104) → produce the narrow candidate palette (102 registry) — and is the seam
// the executor (106) will plug into via `execute`. No model call here; the palette
// must appear without waiting on an LLM.

public enum LegalSkillRuntimeError: Error, Equatable {
    /// No bundled corpus / runtime configured (legacy build without legal enabled).
    case notConfigured
    /// Skill execution lands here until the executor + backend route (issue 106).
    case executorNotImplemented(skillId: String)
}

/// The result of a legal trigger: the routing decision + the palette to render.
public struct LegalPaletteOutcome: Sendable {
    public let decision: LegalRouteDecision
    public let cards: [LegalCandidateCard]

    public init(decision: LegalRouteDecision, cards: [LegalCandidateCard]) {
        self.decision = decision
        self.cards = cards
    }

    public var scene: LegalScene { decision.classification.scene }
    public var stage: LegalStage { decision.classification.stage }
    public var confidence: Double { decision.classification.confidence }
    /// True when the scene is uncertain → the capsule shows a scene-confirm card.
    public var shouldConfirmScene: Bool {
        decision.classification.shouldAskUser || decision.tier == "confirm"
    }
}

public struct LegalSkillRuntime: Sendable {
    /// Badge shown on imported (untrusted) skills in the ⌥L palette (236).
    public static let unvettedBadge = "第三方·未审"

    public let registry: LegalSkillRegistry
    /// Ids of imported skills, so their palette cards can be marked 第三方·未审 (236).
    public let importedSkillIDs: Set<String>
    private let signalLayer: ContextSignalLayer
    private let router: LegalSceneStageRouter
    private let executor: LegalSkillExecutorAPI?
    private let assembler: LegalPromptAssembler
    private let validator: LegalOutputValidator
    private let postProcessor: VerificationPostProcessor

    public init(
        registry: LegalSkillRegistry,
        importedSkillIDs: Set<String> = [],
        signalLayer: ContextSignalLayer = ContextSignalLayer(),
        router: LegalSceneStageRouter = LegalSceneStageRouter(),
        executor: LegalSkillExecutorAPI? = nil,
        assembler: LegalPromptAssembler = LegalPromptAssembler(),
        validator: LegalOutputValidator = LegalOutputValidator(),
        postProcessor: VerificationPostProcessor = VerificationPostProcessor()
    ) {
        self.registry = registry
        self.importedSkillIDs = importedSkillIDs
        self.signalLayer = signalLayer
        self.router = router
        self.executor = executor
        self.assembler = assembler
        self.validator = validator
        self.postProcessor = postProcessor
    }

    /// Compile + load the bundled v0 corpus (103) into a runtime, with an optional
    /// executor (106). nil executor → `execute` throws `notConfigured`. When an
    /// `importedStore` is supplied (122/235), its **generation** skills merge into the
    /// registry (imported rewrite skills are StylePacks, not ⌥L candidates); a bad import
    /// file is skipped rather than failing the whole runtime.
    public static func bundled(
        executor: LegalSkillExecutorAPI? = nil,
        importedStore: ImportedLegalSkillStore? = nil
    ) throws -> LegalSkillRuntime {
        var registry = try LegalSkillRegistry.loadBundled()
        var importedIDs: Set<String> = []
        if let importedStore {
            let compiler = LegalSkillCompiler()
            // Poison-pill guard (猎虫⑤ P1-1): an imported file whose id collides
            // with a bundled skill (or another import) must not throw the whole
            // registry away — `merging` throws, CaptureController's `try?` then
            // nils the runtime, and the ENTIRE ⌥L palette died with a misleading
            // 「法律技能未配置」 until the file was hand-deleted in Finder.
            // Bundled wins; duplicate imports are dropped.
            var seen = Set(registry.skills.map(\.id))
            let imported = ((try? importedStore.loadAllRawMarkdown()) ?? [])
                .compactMap { try? compiler.compile($0) }
                .filter { $0.metadata.kind == .generation }
                .filter { seen.insert($0.id).inserted }
            importedIDs = Set(imported.map(\.id))
            registry = try registry.merging(imported)
        }
        return LegalSkillRuntime(registry: registry, importedSkillIDs: importedIDs, executor: executor)
    }

    // MARK: - Suggest (palette)

    /// Classify the context (104) and attach the palette to render. `now` is injected
    /// (no `Date()` in core). This is what the VM calls on a legal trigger.
    public func route(
        context: ExpressionContext,
        now: Date,
        browserURL: String? = nil,
        profile: LegalPracticeProfile? = nil,
        enabled: Set<String>? = nil
    ) -> LegalPaletteOutcome {
        let bundle = signalLayer.assemble(context: context, browserURL: browserURL, now: now)
        let decision = router.route(bundle, registry: registry)
        return LegalPaletteOutcome(decision: decision, cards: paletteCards(for: decision, profile: profile, enabled: enabled))
    }

    /// The scene-scoped action palette (3–7 法律工作动作). Unlike the router's
    /// auto-candidate set (keyword-narrowed to the single best match), the palette
    /// shows **all** skills in the scene so the user can switch actions; `stage` only
    /// orders the most-relevant first. Always appends 起草本段 (a generic insert action).
    public func suggestSkills(
        scene: LegalScene,
        stage: LegalStage,
        confidence: Double = 0,
        profile: LegalPracticeProfile? = nil,
        enabled: Set<String>? = nil
    ) -> [LegalCandidateCard] {
        let ranked = registry.candidates(scene: scene)
            .filter { enabled == nil || enabled!.contains($0.id) }
            .sorted { lhs, rhs in
                let lApplies = lhs.metadata.sceneLayer.applicableStages.contains(stage) ? 0 : 1
                let rApplies = rhs.metadata.sceneLayer.applicableStages.contains(stage) ? 0 : 1
                return lApplies != rApplies ? lApplies < rApplies : lhs.id < rhs.id
            }
        var cards = ranked.map { skill -> LegalCandidateCard in
            let card = LegalSceneStageRouter.card(from: skill, routingStage: stage, confidence: confidence)
            return importedSkillIDs.contains(skill.id) ? card.addingBadge(Self.unvettedBadge) : card
        }
        cards.append(Self.draftThisParagraphCard(scene: scene, stage: stage, confidence: confidence))
        return cards
    }

    /// Build a runnable card for one specific skill id — a **direct** (non-palette) run,
    /// used by the 划词菜单's 来源辅助检索 / 实务辅助 entries which name the skill outright
    /// instead of routing through scene classification. `nil` when the id isn't in the
    /// registry. The card is identical to the one the palette would produce for that skill
    /// (same scene/stage/badges), so execution + run-history stay consistent.
    public func candidateCard(forSkillId id: String) -> LegalCandidateCard? {
        guard let skill = registry.skill(id: id) else { return nil }
        let stage = skill.metadata.sceneLayer.applicableStages.first ?? .matterIntake
        let card = LegalSceneStageRouter.card(from: skill, routingStage: stage, confidence: 1)
        return importedSkillIDs.contains(id) ? card.addingBadge(Self.unvettedBadge) : card
    }

    // MARK: - Execute (stub until 106)

    /// Run a chosen skill (106): assemble the prompt, call the backend, validate the
    /// model JSON (decode → one repair pass → fallback text). Never throws on a
    /// malformed model reply — it degrades to a `FallbackTextCard`. Throws only when
    /// the runtime/executor isn't configured or the card has no compiled skill (the
    /// `generic.*` palette actions, e.g. 起草本段, are a 106 tail). `route` is the
    /// privacy-derived `ModelRoute` (110); `localOnly` never reaches cloud.
    public func execute(
        card: LegalCandidateCard,
        context: ExpressionContext,
        route: ModelRoute = .cloudAllowed
    ) async throws -> LegalSkillResponse {
        guard let executor else { throw LegalSkillRuntimeError.notConfigured }
        guard let skill = registry.skill(id: card.skillId) else {
            throw LegalSkillRuntimeError.executorNotImplemented(skillId: card.skillId)
        }

        let payload = LegalContextPayload(
            selectedText: context.selectedText ?? "",
            scene: card.scene, stage: card.stage,
            appName: context.appName ?? "")
        let prompt = assembler.assemble(skill: skill, context: payload)
        let request = LegalSkillExecutionRequest(
            skillId: skill.id, systemPrompt: prompt.system, userPrompt: prompt.user,
            modelRoute: route, purpose: .legalSkill)
        let response = try await executor.executeSkill(request)

        let envelope = LegalOutputValidator.Envelope(
            runId: response.runId, skillId: skill.id, scene: card.scene, stage: card.stage)
        let validated = await validator.validate(rawOutput: response.output, envelope: envelope) { broken in
            let repair = assembler.repairPrompt(brokenOutput: broken)
            let repairRequest = LegalSkillExecutionRequest(
                skillId: skill.id, systemPrompt: repair.system, userPrompt: repair.user,
                modelRoute: route, purpose: .legalSkill, isRepair: true)
            return try await executor.executeSkill(repairRequest).output
        }
        // 108: back-fill a pending [待核] anchor for any fact coordinate the model missed.
        // 487: turn the model's extracted `caseFacts` into a deterministic 检索作战图 card.
        return CaseRetrievalReportPostProcessor.process(postProcessor.backfill(validated))
    }

    public func supportsSearchVerification(route: ModelRoute) -> Bool {
        executor?.supportsSearchVerification(route: route) ?? false
    }

    public func searchVerification(_ anchor: VerificationAnchor, route: ModelRoute) async throws -> VerifiedSource? {
        guard let executor else { throw LegalSkillRuntimeError.notConfigured }
        return try await executor.searchVerification(anchor, route: route)
    }

    /// 488 — 找类案：web-AI 候选 → `CaseCandidateScreener`（案号闸 + 案号交叉验证 + 两高配额）。
    /// 交叉验证复用 `searchVerification`（引号案号 → 找到独立来源即视为命中）。`currentYear` 注入
    /// （core 不用 `Date()`）。
    public func findSimilarCases(query: String, route: ModelRoute, currentYear: Int) async throws -> [ScreenedCase] {
        guard let executor else { throw LegalSkillRuntimeError.notConfigured }
        let candidates = try await executor.searchCaseCandidates(query, route: route)
        guard !candidates.isEmpty else { return [] }
        return await CaseCandidateScreener(currentYear: currentYear).screen(candidates) { caseNumber in
            let anchor = VerificationAnchor(
                id: caseNumber, label: caseNumber, kind: .caseLaw, query: "\"\(caseNumber)\"")
            let source = try? await executor.searchVerification(anchor, route: route)
            if let url = source?.url { return [url] }
            return []
        }
    }

    // MARK: - Internals

    private func paletteCards(for decision: LegalRouteDecision, profile: LegalPracticeProfile?, enabled: Set<String>? = nil) -> [LegalCandidateCard] {
        switch decision {
        case let .autoCandidates(c, _), let .confirmScene(c, _):
            return suggestSkills(scene: c.scene, stage: c.stage, confidence: c.confidence, profile: profile, enabled: enabled)
        case let .genericLegalActions(_, actions):
            return actions
        case .needsSelection:
            return []
        }
    }

    /// 起草本段 — a generic "draft from the current scene/stage" action that does not
    /// map to a specific authored skill (executor 106 resolves the `generic.*` namespace).
    static func draftThisParagraphCard(scene: LegalScene, stage: LegalStage, confidence: Double) -> LegalCandidateCard {
        LegalCandidateCard(
            id: "generic.draftParagraph",
            skillId: "generic.draftParagraph",
            title: "起草本段",
            subtitle: "依当前场景起草，可插入；新坐标标 [待核]",
            scene: scene,
            stage: stage,
            confidence: confidence,
            badges: [LegalSceneStageRouter.sceneLabel(scene), "待核"],
            requiredInputs: [.selectedText, .textBeforeCursor],
            preview: nil,
            action: .executeSkill(skillId: "generic.draftParagraph")
        )
    }
}
