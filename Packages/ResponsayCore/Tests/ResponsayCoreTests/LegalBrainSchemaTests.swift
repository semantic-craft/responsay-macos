import Foundation
import Testing
@testable import ResponsayCore

// MARK: - Legal Brain core schema round-trip (issue 101)
//
// Stable round-trip = encode → decode → re-encode and compare bytes (sortedKeys), so we
// don't need Equatable on every type and still catch lossy Codable. Covers the tricky
// enums-with-associated-values (LegalOutputCard, LegalCandidateAction).

private func roundTripStable<T: Codable>(_ value: T) throws -> Bool {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let first = try encoder.encode(value)
    let decoded = try JSONDecoder().decode(T.self, from: first)
    let second = try encoder.encode(decoded)
    return first == second
}

@Test func legalSkillMetadata_roundTrips() throws {
    let meta = LegalSkillMetadata(
        schemaVersion: "LEGAL_SKILL/v1",
        id: "practice.evidence_review.cn",
        title: "证据论证链",
        domain: .litigation,
        language: "zh-CN",
        triggers: LegalSkillTriggers(
            keywords: ["事实与理由", "证据", "违约"],
            appHints: ["Microsoft Word"],
            windowTitleHints: ["代理词"],
            minSelectedTextLength: 20
        ),
        inputs: [.selectedText, .textBeforeCursor, .windowTitle, .factCoordinates],
        sceneLayer: SceneLayer(
            scene: .litigation,
            applicableStages: [.briefDrafting, .evidenceReview],
            preconditions: ["用户已选中一段结论性主张"],
            nextActionCandidates: ["evidence_gap_check", "verification_search"]
        ),
        reasoningKernel: ReasoningKernel(
            mandatoryMapping: ["claim", "legal_element", "evidence", "probative_force"],
            forbidden: ["不得编造案号"]
        ),
        outputCards: [.evidenceArgumentMatrix, .verificationTodos, .nextStepDecisionTree],
        risk: LegalSkillRisk(level: .high, disclaimer: "需律师核验。")
    )
    #expect(try roundTripStable(meta))
}

@Test func legalCandidateAction_associatedValueRoundTrips() throws {
    #expect(try roundTripStable(LegalCandidateAction.executeSkill(skillId: "x.y.cn")))
    #expect(try roundTripStable(LegalCandidateAction.askUserToSelectScene))
    #expect(try roundTripStable(LegalCandidateAction.openSettings))
}

@Test func legalCandidateCard_roundTrips() throws {
    let card = LegalCandidateCard(
        id: "c1",
        skillId: "practice.evidence_review.cn",
        title: "证据论证链",
        scene: .litigation,
        stage: .briefDrafting,
        confidence: 0.86,
        badges: ["诉讼", "待核"],
        requiredInputs: [.selectedText],
        action: .executeSkill(skillId: "practice.evidence_review.cn")
    )
    #expect(try roundTripStable(card))
}

@Test func verificationAnchor_defaultsToPending() throws {
    let anchor = VerificationAnchor(
        id: "a1",
        label: "《民法典》第577条",
        kind: .law,
        query: "民法典 第577条 违约责任",
        preferredSources: [.govLaw, .qwenSearch]
    )
    #expect(anchor.status == .pending)
    #expect(try roundTripStable(anchor))
}

@Test func legalSkillResponse_withMixedCards_roundTrips() throws {
    let response = LegalSkillResponse(
        runId: "run-1",
        skillId: "practice.evidence_review.cn",
        scene: .litigation,
        stage: .briefDrafting,
        summary: "证据论证链草稿",
        cards: [
            .evidenceArgumentMatrix(EvidenceArgumentMatrixCard(
                title: "证据-主张矩阵",
                rows: [EvidenceArgumentRow(
                    id: "r1",
                    claim: "被告负有付款义务",
                    legalElement: "合同成立",
                    factToProve: "采购合同签订",
                    evidence: "采购合同",
                    authenticity: .medium,
                    legality: .strong,
                    relevance: .strong,
                    probativeForce: .medium,
                    rebuttalRisk: "若未盖章需补强",
                    gapFilling: "补签收单",
                    verificationAnchorIds: ["a1"]
                )]
            )),
            .counterargument(CounterargumentCard(
                title: "反方观点",
                thesis: "平台是个人信息处理者",
                implicitPremises: ["平台决定处理目的"],
                items: [CounterargumentItem(
                    id: "ca1",
                    counterargument: "平台仅提供技术服务",
                    basis: "委托处理结构",
                    replyStrategy: "回到实质控制能力"
                )]
            )),
            .cnkiQuery(CNKIQueryCard(
                title: "CNKI 检索式",
                expertQuery: "SU=('个人信息处理者') AND SU=('自动化决策')"
            )),
            .fallbackText(FallbackTextCard(title: "原始输出", text: "…"))
        ],
        insertables: [InsertableLegalText(
            id: "ins1",
            title: "证据链说明段",
            text: "上述证据共同形成连续证明链条。",
            insertPolicy: .noInsert,
            containsPendingVerification: true
        )],
        verificationAnchors: [VerificationAnchor(
            id: "a1",
            label: "《民法典》第577条",
            kind: .law,
            query: "民法典 577 违约"
        )],
        warnings: []
    )
    #expect(response.schemaVersion == LegalSkillResponse.schemaVersionV1)
    #expect(try roundTripStable(response))
}

@Test func legalPracticeProfile_roundTrips() throws {
    let profile = LegalPracticeProfile(
        id: "p1",
        role: .legalScholar,
        primaryDomains: [.academicWriting, .privacy],
        jurisdictions: ["CN"],
        writingModes: [.academicArticle],
        citationPreference: .legalCitationDraft,
        sourcePriority: [.cnki, .govLaw],
        redLines: ["不伪造脚注"],
        escalationMatrix: [EscalationRule(id: "e1", condition: "涉及未公开材料", action: "本地模型")],
        modelPreference: .localFirst,
        privacyPreference: .selectedTextOnly,
        createdAt: "2026-06-07T00:00:00Z",
        updatedAt: "2026-06-07T00:00:00Z"
    )
    #expect(try roundTripStable(profile))
}

@Test func legalContextPayload_and_classification_roundTrip() throws {
    let payload = LegalContextPayload(
        selectedText: "被告长期拖欠货款……",
        scene: .litigation,
        stage: .briefDrafting,
        appName: "Microsoft Word",
        contextScope: .selectedTextOnly,
        source: .accessibility
    )
    #expect(payload.source == .accessibility)
    #expect(try roundTripStable(payload))

    let classification = SceneStageClassification(
        scene: .litigation,
        stage: .briefDrafting,
        confidence: 0.86,
        reasons: ["windowTitle 含 代理词"],
        shouldAskUser: false
    )
    #expect(try roundTripStable(classification))
}
