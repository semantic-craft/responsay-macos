import Foundation

// 372 — legal DECISIONS live in `LegalCaptureCoordinator` (routing, context
// assembly, scene classification, privacy gate, run building). This extension is
// now a thin orchestrator: call the coordinator, assign results to @Observable
// state, drive the phase machine. The insertion/verification-tag side effects
// (which touch `inserter`) intentionally stay here.
extension QuickCaptureViewModel {
    /// Scene classification for a selection. Used by the 任意提问 legal/general router
    /// (`QuickCaptureViewModel+Ask`); the standalone legal palette that also consumed it
    /// was retired (划词技能互动) — skills now run directly via `runLegalSkillOnSelection`.
    public func evaluateScene(text: String) -> SceneStageClassification? {
        legal.evaluateScene(text: text)
    }

    /// Direct (non-palette) run of one named skill on a captured selection — the 划词菜单's
    /// 来源辅助检索 / 划词生成 entries. Sets the transcript, builds the skill's card and runs it
    /// through the same privacy-gated path as a palette pick (so the send-confirm / route
    /// logic is shared, not duplicated). Shows a one-card review while it executes.
    public func runLegalSkillOnSelection(skillId: String, text: String) async {
        guard legal.isConfigured else { enterError("法律技能未配置。"); return }
        guard let card = legal.candidateCard(forSkillId: skillId) else {
            enterError("未找到技能：\(skillId)"); return
        }
        transcript = text
        legalCandidates = [card]
        phase = .review
        await selectLegalCandidate(card)
    }

    public func selectLegalCandidate(_ card: LegalCandidateCard) async {
        guard legal.isConfigured else { enterError("法律技能未配置。"); return }
        let decision = legal.privacyDecision(transcript: transcript)
        if decision.isBlocked {
            enterError(decision.reasons.first ?? "当前上下文已被隐私策略阻止发送。")
            return
        }
        if decision.requiresUserConfirm {
            pendingLegalCard = card
            legalSendConfirm = decision
            return
        }
        await runLegalSkill(card, route: decision.route)
    }

    public func confirmLegalSend() async {
        guard let card = pendingLegalCard else { return }
        legalSendConfirm = nil
        pendingLegalCard = nil
        await runLegalSkill(card, route: .cloudAllowed)
    }

    public func cancelLegalSend() {
        legalSendConfirm = nil
        pendingLegalCard = nil
    }

    func runLegalSkill(_ card: LegalCandidateCard, route: ModelRoute) async {
        guard legal.isConfigured else { enterError("法律技能未配置。"); return }
        let context = legal.executionContext(transcript: transcript)
        do {
            legalResponse = try await legal.execute(card: card, context: context, route: route)
            legalResponseRoute = route
            legal.recordRun(card: card, context: context, route: route, transcript: transcript)
            await deliverLegalOutput()
        } catch {
            enterError("「\(card.title)」执行失败：\(error.localizedDescription)")
        }
    }

    /// 475 — card (default) vs 直接上屏. In insert mode the body paragraph is pushed via the
    /// existing clipboard-safe inserter and the panel is skipped; secure-input / no-body fall
    /// back to the card (the resolver owns those guards). `insertLegalText` runs *before* the
    /// panel state clears so it still sees `legalResponse.verificationAnchors` for [待核] tags.
    func deliverLegalOutput() async {
        guard let response = legalResponse else { return }
        let preference = legalOutputPreferenceProvider?() ?? .card
        // 安全上下文不再压制直接上屏:交付方式只看用户的输出偏好(卡片 / 直接上屏)。
        let delivery = LegalOutputDeliveryResolver().resolve(
            preference: preference, isSecureInput: false, response: response)
        guard case let .insert(text) = delivery else { return }   // .card → panel shows as usual
        await insertLegalText(text)
        legalResponse = nil
        legalResponseRoute = nil
        phase = .idle
    }

    /// The 对抗 the current result card can continue into (反方观点 → 审稿人↔作者;
    /// 思路推演 → 评审↔提案人), or `nil` when this skill has none or no assistant is wired.
    /// Drives whether the panel offers「继续对抗」at all.
    public var legalResultDebateScript: DebateScript? {
        guard debateSink != nil, let response = legalResponse else { return nil }
        return DebateScript.forSkill(id: response.skillId)
    }

    /// 继续对抗 — hand the card the user just read to the Voice Assistant as the grounded
    /// subject, then clear the panel so the 对抗 owns the screen. The skill's card played the
    /// opening round, so the session starts on the 加压 side (`DebateStance.atRound(0)`).
    public func continueLegalResultAsDebate() {
        guard let script = legalResultDebateScript, let response = legalResponse else { return }
        debateSink?(DebateSeed.subject(from: response), script)
        legalResponse = nil
        legalResponseRoute = nil
        phase = .idle
    }

    /// 488 找类案：only when the response route allows search (默认关，用户点才触发)。`currentYear`
    /// injected by the macOS caller (core 不用 `Date()`). Results land in `legalCaseCandidates`,
    /// each screened by the 案号 gate + cross-check + 两高配额; nothing fabricated reaches the panel.
    public func findSimilarCases(query: String, currentYear: Int) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, legalSearchPermission.isSearchEnabled else { return }
        isFindingCases = true
        defer { isFindingCases = false }
        do {
            legalCaseCandidates = try await legal.findSimilarCases(
                query: trimmed, route: legalResponseRoute, currentYear: currentYear)
        } catch {
            enterError("找类案失败：\(error.localizedDescription)")
        }
    }

    public var legalSearchPermission: SearchPrivacyGate.SearchPermission {
        legal.searchPermission(route: legalResponseRoute)
    }

    public func verifyLegalAnchor(_ anchor: VerificationAnchor) async throws -> VerifiedSource? {
        try await legal.searchVerification(anchor, route: legalResponseRoute)
    }

    public func confirmLegalAnchor(_ anchor: VerificationAnchor, source: VerifiedSource) {
        guard let response = legalResponse else { return }
        var anchors = response.verificationAnchors
        guard let index = anchors.firstIndex(where: { $0.id == anchor.id }) else { return }
        SearchVerificationService.applyResult(source, to: &anchors[index])
        legalResponse = LegalSkillResponse(
            schemaVersion: response.schemaVersion,
            runId: response.runId,
            skillId: response.skillId,
            scene: response.scene,
            stage: response.stage,
            summary: response.summary,
            cards: response.cards,
            insertables: response.insertables,
            verificationAnchors: anchors,
            warnings: response.warnings)
    }

    public func insertLegalText(_ text: String, skipsTagging: Bool = false) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let tagged = skipsTagging ? text : VerificationPostProcessor().ensureTags(
            in: text, anchors: legalResponse?.verificationAnchors ?? [])
        do {
            try await inserter.insert(tagged)
        } catch {
            enterError(error.localizedDescription)
        }
    }
}
