import Foundation

// MARK: - 246/487 检索焦点 (LLM 抽取) / 检索作战图 (app 确定性渲染) 卡片
//
// `LegalOutputCard` cases live in `LegalSkillResponse.swift`; these are their payloads.

/// One 争议焦点 + the case fields the LLM extracted for it. The LLM emits these (`caseFacts`
/// card); query/URL construction stays deterministic app-side (`CaseRetrievalPlanner`).
public struct CaseFactsFocus: Codable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let caseNumber: String?
    public let causeOfAction: String?
    public let year: String?
    public let keywords: String?
    public let charge: String?

    public init(id: String, label: String, caseNumber: String? = nil, causeOfAction: String? = nil,
                year: String? = nil, keywords: String? = nil, charge: String? = nil) {
        self.id = id; self.label = label; self.caseNumber = caseNumber
        self.causeOfAction = causeOfAction; self.year = year; self.keywords = keywords; self.charge = charge
    }

    var facts: CaseFacts {
        CaseFacts(caseNumber: caseNumber, causeOfAction: causeOfAction,
                  year: year, keywords: keywords, charge: charge)
    }
}

/// LLM input card: the focuses it extracted. Consumed (and removed) by
/// `CaseRetrievalReportPostProcessor`, which replaces it with a `caseRetrievalReport` card.
public struct CaseFactsCard: Codable, Sendable {
    public let title: String
    public let focuses: [CaseFactsFocus]

    public init(title: String, focuses: [CaseFactsFocus]) {
        self.title = title; self.focuses = focuses
    }
}

/// App-built display card: the deterministic 检索作战图 Markdown (safety note + per-channel
/// 检索式 + 直达链接). The model never emits this (it would hallucinate URLs); the
/// post-processor builds it from `CaseFactsCard`.
public struct CaseRetrievalReportCard: Codable, Sendable {
    public let title: String
    public let markdown: String

    public init(title: String, markdown: String) {
        self.title = title; self.markdown = markdown
    }
}
