import Foundation

// MARK: - Structured skill output contract
//
// The deterministic JSON a skill execution must return (issue 106 validates it; issue 107
// renders it). Models output this shape; failures fall back to `.fallbackText` (spec §10).
// Fact coordinates are carried as `verificationAnchors` and referenced by id from cards.

public enum EvidenceAssessment: String, Codable, Sendable {
    case strong, medium, weak, unknown
}

public enum ProbativeForce: String, Codable, Sendable {
    case strong, medium, weak, unknown
}

// MARK: Card: 证据论证矩阵 (anchor A)

public struct EvidenceArgumentRow: Codable, Sendable, Identifiable {
    public let id: String
    public let claim: String
    public let legalElement: String
    public let factToProve: String
    public let evidence: String
    public let authenticity: EvidenceAssessment
    public let legality: EvidenceAssessment
    public let relevance: EvidenceAssessment
    public let probativeForce: ProbativeForce
    public let rebuttalRisk: String
    public let gapFilling: String
    public let verificationAnchorIds: [String]

    public init(
        id: String,
        claim: String,
        legalElement: String,
        factToProve: String,
        evidence: String,
        authenticity: EvidenceAssessment,
        legality: EvidenceAssessment,
        relevance: EvidenceAssessment,
        probativeForce: ProbativeForce,
        rebuttalRisk: String,
        gapFilling: String,
        verificationAnchorIds: [String] = []
    ) {
        self.id = id
        self.claim = claim
        self.legalElement = legalElement
        self.factToProve = factToProve
        self.evidence = evidence
        self.authenticity = authenticity
        self.legality = legality
        self.relevance = relevance
        self.probativeForce = probativeForce
        self.rebuttalRisk = rebuttalRisk
        self.gapFilling = gapFilling
        self.verificationAnchorIds = verificationAnchorIds
    }
}

public struct EvidenceArgumentMatrixCard: Codable, Sendable {
    public let title: String
    public let rows: [EvidenceArgumentRow]

    public init(title: String, rows: [EvidenceArgumentRow]) {
        self.title = title
        self.rows = rows
    }
}

// MARK: Card: 主张-证据映射

public struct ClaimEvidenceMapping: Codable, Sendable, Identifiable {
    public let id: String
    public let evidence: String
    public let supportsClaims: [String]
    public let note: String?

    public init(id: String, evidence: String, supportsClaims: [String], note: String? = nil) {
        self.id = id
        self.evidence = evidence
        self.supportsClaims = supportsClaims
        self.note = note
    }
}

public struct ClaimEvidenceMapCard: Codable, Sendable {
    public let title: String
    public let claims: [String]
    public let mappings: [ClaimEvidenceMapping]

    public init(title: String, claims: [String], mappings: [ClaimEvidenceMapping]) {
        self.title = title
        self.claims = claims
        self.mappings = mappings
    }
}

// MARK: Card: 反方观点 (anchor B)

public struct CounterargumentItem: Codable, Sendable, Identifiable {
    public let id: String
    public let counterargument: String
    public let basis: String
    public let replyStrategy: String

    public init(id: String, counterargument: String, basis: String, replyStrategy: String) {
        self.id = id
        self.counterargument = counterargument
        self.basis = basis
        self.replyStrategy = replyStrategy
    }
}

public struct CounterargumentCard: Codable, Sendable {
    public let title: String
    public let thesis: String
    public let implicitPremises: [String]
    public let items: [CounterargumentItem]

    public init(title: String, thesis: String, implicitPremises: [String], items: [CounterargumentItem]) {
        self.title = title
        self.thesis = thesis
        self.implicitPremises = implicitPremises
        self.items = items
    }
}

// MARK: Card: CNKI 检索式

public struct CNKIQueryCard: Codable, Sendable {
    public let title: String
    public let expertQuery: String        // CNKI 专业检索式, e.g. SU=('…') AND SU=('…')
    public let plainQuery: String?

    public init(title: String, expertQuery: String, plainQuery: String? = nil) {
        self.title = title
        self.expertQuery = expertQuery
        self.plainQuery = plainQuery
    }
}

// MARK: Card: 下一步决策树

public struct NextStepOption: Codable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let condition: String
    public let rationale: String

    public init(id: String, label: String, condition: String, rationale: String) {
        self.id = id
        self.label = label
        self.condition = condition
        self.rationale = rationale
    }
}

public struct NextStepDecisionTreeCard: Codable, Sendable {
    public let title: String
    public let options: [NextStepOption]

    public init(title: String, options: [NextStepOption]) {
        self.title = title
        self.options = options
    }
}

// MARK: Card: 待核清单 / 降级文本

public struct VerificationTodosCard: Codable, Sendable {
    public let title: String
    public let anchorIds: [String]

    public init(title: String, anchorIds: [String]) {
        self.title = title
        self.anchorIds = anchorIds
    }
}

public struct InsertableParagraphCard: Codable, Sendable {
    public let title: String
    public let text: String
    public let containsPendingVerification: Bool

    public init(title: String, text: String, containsPendingVerification: Bool) {
        self.title = title
        self.text = text
        self.containsPendingVerification = containsPendingVerification
    }
}

public struct FallbackTextCard: Codable, Sendable {
    public let title: String
    public let text: String

    public init(title: String, text: String) {
        self.title = title
        self.text = text
    }
}

// MARK: Card: 法律分析

public struct LegalAnalysisItem: Codable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let content: String

    public init(id: String, label: String, content: String) {
        self.id = id
        self.label = label
        self.content = content
    }
}

public struct LegalAnalysisCard: Codable, Sendable {
    public let title: String
    public let items: [LegalAnalysisItem]

    public init(title: String, items: [LegalAnalysisItem]) {
        self.title = title
        self.items = items
    }
}

// MARK: Card: 诉讼策略推荐

public struct StrategyRecommendationItem: Codable, Sendable, Identifiable {
    public let id: String
    public let strategy: String
    public let rationale: String

    public init(id: String, strategy: String, rationale: String) {
        self.id = id
        self.strategy = strategy
        self.rationale = rationale
    }
}

public struct StrategyRecommendationCard: Codable, Sendable {
    public let title: String
    public let recommendations: [StrategyRecommendationItem]

    public init(title: String, recommendations: [StrategyRecommendationItem]) {
        self.title = title
        self.recommendations = recommendations
    }
}

// MARK: Output card sum type
// concept_map / risk_matrix (declared in `LegalOutputCardType`) map to `.fallbackText` (spec §7).

public enum LegalOutputCard: Codable, Sendable {
    case evidenceArgumentMatrix(EvidenceArgumentMatrixCard)
    case claimEvidenceMap(ClaimEvidenceMapCard)
    case counterargument(CounterargumentCard)
    case nextStepDecisionTree(NextStepDecisionTreeCard)
    case verificationTodos(VerificationTodosCard)
    case cnkiQuery(CNKIQueryCard)
    case insertableParagraph(InsertableParagraphCard)
    case legalAnalysis(LegalAnalysisCard)
    case strategyRecommendation(StrategyRecommendationCard)
    case caseFacts(CaseFactsCard)
    case caseRetrievalReport(CaseRetrievalReportCard)
    case fallbackText(FallbackTextCard)

    // Externally-tagged Codable `{"<caseName>": <payload>}` — the shape an LLM emits (synthesized enum Codable's `_0` wrapper would force every reply to fallback).
    private enum CodingKeys: String, CodingKey {
        case evidenceArgumentMatrix, claimEvidenceMap, counterargument, nextStepDecisionTree
        case verificationTodos, cnkiQuery, insertableParagraph, fallbackText
        case legalAnalysis, strategyRecommendation, caseFacts, caseRetrievalReport
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try c.decodeIfPresent(EvidenceArgumentMatrixCard.self, forKey: .evidenceArgumentMatrix) { self = .evidenceArgumentMatrix(v); return }
        if let v = try c.decodeIfPresent(ClaimEvidenceMapCard.self, forKey: .claimEvidenceMap) { self = .claimEvidenceMap(v); return }
        if let v = try c.decodeIfPresent(CounterargumentCard.self, forKey: .counterargument) { self = .counterargument(v); return }
        if let v = try c.decodeIfPresent(NextStepDecisionTreeCard.self, forKey: .nextStepDecisionTree) { self = .nextStepDecisionTree(v); return }
        if let v = try c.decodeIfPresent(VerificationTodosCard.self, forKey: .verificationTodos) { self = .verificationTodos(v); return }
        if let v = try c.decodeIfPresent(CNKIQueryCard.self, forKey: .cnkiQuery) { self = .cnkiQuery(v); return }
        if let v = try c.decodeIfPresent(InsertableParagraphCard.self, forKey: .insertableParagraph) { self = .insertableParagraph(v); return }
        if let v = try c.decodeIfPresent(LegalAnalysisCard.self, forKey: .legalAnalysis) { self = .legalAnalysis(v); return }
        if let v = try c.decodeIfPresent(StrategyRecommendationCard.self, forKey: .strategyRecommendation) { self = .strategyRecommendation(v); return }
        if let v = try c.decodeIfPresent(CaseFactsCard.self, forKey: .caseFacts) { self = .caseFacts(v); return }
        if let v = try c.decodeIfPresent(CaseRetrievalReportCard.self, forKey: .caseRetrievalReport) { self = .caseRetrievalReport(v); return }
        if let v = try c.decodeIfPresent(FallbackTextCard.self, forKey: .fallbackText) { self = .fallbackText(v); return }
        throw DecodingError.dataCorrupted(.init(
            codingPath: decoder.codingPath, debugDescription: "Unknown legal output card type"))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .evidenceArgumentMatrix(v): try c.encode(v, forKey: .evidenceArgumentMatrix)
        case let .claimEvidenceMap(v):       try c.encode(v, forKey: .claimEvidenceMap)
        case let .counterargument(v):        try c.encode(v, forKey: .counterargument)
        case let .nextStepDecisionTree(v):   try c.encode(v, forKey: .nextStepDecisionTree)
        case let .verificationTodos(v):      try c.encode(v, forKey: .verificationTodos)
        case let .cnkiQuery(v):              try c.encode(v, forKey: .cnkiQuery)
        case let .insertableParagraph(v):    try c.encode(v, forKey: .insertableParagraph)
        case let .legalAnalysis(v):          try c.encode(v, forKey: .legalAnalysis)
        case let .strategyRecommendation(v): try c.encode(v, forKey: .strategyRecommendation)
        case let .caseFacts(v):              try c.encode(v, forKey: .caseFacts)
        case let .caseRetrievalReport(v):    try c.encode(v, forKey: .caseRetrievalReport)
        case let .fallbackText(v):           try c.encode(v, forKey: .fallbackText)
        }
    }
}

// MARK: Insertable text (response-level)

public struct InsertableLegalText: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let text: String
    public let insertPolicy: InsertPolicy        // reuses the existing capture InsertPolicy
    public let containsPendingVerification: Bool

    public init(
        id: String,
        title: String,
        text: String,
        insertPolicy: InsertPolicy,
        containsPendingVerification: Bool
    ) {
        self.id = id
        self.title = title
        self.text = text
        self.insertPolicy = insertPolicy
        self.containsPendingVerification = containsPendingVerification
    }
}

// MARK: Top-level response

public struct LegalSkillResponse: Codable, Sendable {
    public static let schemaVersionV1 = "LEGAL_OUTPUT/v1"

    public let schemaVersion: String
    public let runId: String
    public let skillId: String
    public let scene: LegalScene
    public let stage: LegalStage
    public let summary: String
    public let cards: [LegalOutputCard]
    public let insertables: [InsertableLegalText]
    public let verificationAnchors: [VerificationAnchor]
    public let warnings: [String]

    public init(
        schemaVersion: String = LegalSkillResponse.schemaVersionV1,
        runId: String,
        skillId: String,
        scene: LegalScene,
        stage: LegalStage,
        summary: String,
        cards: [LegalOutputCard],
        insertables: [InsertableLegalText] = [],
        verificationAnchors: [VerificationAnchor] = [],
        warnings: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.runId = runId
        self.skillId = skillId
        self.scene = scene
        self.stage = stage
        self.summary = summary
        self.cards = cards
        self.insertables = insertables
        self.verificationAnchors = verificationAnchors
        self.warnings = warnings
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, runId, skillId, scene, stage, summary, cards, insertables, verificationAnchors, warnings
    }

    /// Tolerant decode: models routinely omit empty `insertables` / `warnings` (and
    /// sometimes `cards` / `verificationAnchors`). Default those to `[]` instead of
    /// failing the whole decode, so a well-shaped reply isn't pushed to fallback over a
    /// missing empty array. The envelope fields are injected by the client (106).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(String.self, forKey: .schemaVersion) ?? Self.schemaVersionV1
        runId = try c.decode(String.self, forKey: .runId)
        skillId = try c.decode(String.self, forKey: .skillId)
        scene = try c.decode(LegalScene.self, forKey: .scene)
        stage = try c.decode(LegalStage.self, forKey: .stage)
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        cards = try c.decodeIfPresent([LegalOutputCard].self, forKey: .cards) ?? []
        insertables = try c.decodeIfPresent([InsertableLegalText].self, forKey: .insertables) ?? []
        verificationAnchors = try c.decodeIfPresent([VerificationAnchor].self, forKey: .verificationAnchors) ?? []
        warnings = try c.decodeIfPresent([String].self, forKey: .warnings) ?? []
    }
}
