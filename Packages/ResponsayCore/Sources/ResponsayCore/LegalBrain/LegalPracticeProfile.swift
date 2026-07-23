import Foundation

// MARK: - Cold-start practice profile
//
// Stable per-user preferences captured in a ≤2-minute cold start (issue 109). Injected
// (minimal subset only) into prompt assembly (issue 106) and biases the router (issue 104).
// Persisted via LegalProfileStore (SQLite, issue 109). Never carries past full materials.

public enum LegalUserRole: String, Codable, Sendable, CaseIterable {
    case legalScholar
    case student
    case practitioner
}

public enum LegalWritingMode: String, Codable, Sendable, CaseIterable {
    case academicArticle
    case litigationBrief
    case legalMemo
    case contractReview
    case productReview
}

public enum CitationPreference: String, Codable, Sendable {
    case legalCitationDraft   // 法学引注草稿 + 待核 (default for 法学研究者)
    case bluebook
    case plainFootnote
    case firmMemo
}

public enum SourcePreference: String, Codable, Sendable, CaseIterable {
    case govLaw
    case pkulaw
    case cnki
    case baiduScholar
    case internalKnowledgeBase
}

public enum ModelPreference: String, Codable, Sendable {
    case localFirst
    case cloudFirst
    case askEachTime
}

public enum PrivacyPreference: String, Codable, Sendable {
    case selectedTextOnly
    case allowLocalHeading
    case allowSurrounding
}

public struct EscalationRule: Codable, Sendable, Identifiable {
    public let id: String
    public let condition: String   // 如 "涉及客户秘密" / "涉及出境" / "涉及诉讼时效"
    public let action: String      // 如 "本地模型" / "禁止云端" / "提示人工核验"

    public init(id: String, condition: String, action: String) {
        self.id = id
        self.condition = condition
        self.action = action
    }
}

public struct LegalPracticeProfile: Codable, Sendable, Identifiable {
    public let id: String
    public var role: LegalUserRole
    public var primaryDomains: [LegalScene]
    public var jurisdictions: [String]            // 如 "CN" / "EU" / "GDPR" / "Guangdong"
    public var writingModes: [LegalWritingMode]
    public var citationPreference: CitationPreference
    public var sourcePriority: [SourcePreference]
    public var redLines: [String]
    public var escalationMatrix: [EscalationRule]
    public var modelPreference: ModelPreference
    public var privacyPreference: PrivacyPreference
    public var createdAt: String
    public var updatedAt: String

    public init(
        id: String,
        role: LegalUserRole,
        primaryDomains: [LegalScene] = [],
        jurisdictions: [String] = [],
        writingModes: [LegalWritingMode] = [],
        citationPreference: CitationPreference = .legalCitationDraft,
        sourcePriority: [SourcePreference] = [],
        redLines: [String] = [],
        escalationMatrix: [EscalationRule] = [],
        modelPreference: ModelPreference = .askEachTime,
        privacyPreference: PrivacyPreference = .selectedTextOnly,
        createdAt: String,
        updatedAt: String
    ) {
        self.id = id
        self.role = role
        self.primaryDomains = primaryDomains
        self.jurisdictions = jurisdictions
        self.writingModes = writingModes
        self.citationPreference = citationPreference
        self.sourcePriority = sourcePriority
        self.redLines = redLines
        self.escalationMatrix = escalationMatrix
        self.modelPreference = modelPreference
        self.privacyPreference = privacyPreference
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
