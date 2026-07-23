import Foundation

// MARK: - 107 LegalCardRenderer
//
// Deterministic mapping from `LegalSkillResponse.cards` to display titles + insert
// affordances. Pure / Foundation-only so the rendering decisions (what is insertable,
// what carries [待核], what is copy-only) are testable without SwiftUI. The macOS
// `LegalSkillOutputView` consumes this; unknown/failed cards never become an insert.

/// Which insert button a card backs. Reference cards (matrix/counterargument/…) have none.
public enum LegalInsertKind: String, Sendable, Equatable {
    case body                // 插入正文
    case verificationTodos   // 插入待核清单
    case query               // 插入检索式
}

/// A concrete insert action surfaced under a card. Absent for display-only / fallback cards.
public struct LegalInsertAffordance: Sendable, Equatable {
    public let kind: LegalInsertKind
    public let label: String
    public let text: String
    public let containsPending: Bool      // text carries [待核] coordinates

    public init(kind: LegalInsertKind, label: String, text: String, containsPending: Bool) {
        self.kind = kind
        self.label = label
        self.text = text
        self.containsPending = containsPending
    }
}

public struct LegalCardRenderer: Sendable {
    public init() {}

    /// Every insert affordance in a response, in card order. Fallback / reference cards
    /// contribute none (insert disabled — the view still offers copy).
    public func affordances(for response: LegalSkillResponse) -> [LegalInsertAffordance] {
        response.cards.compactMap { affordance(for: $0, anchors: response.verificationAnchors) }
    }

    func affordance(for card: LegalOutputCard, anchors: [VerificationAnchor]) -> LegalInsertAffordance? {
        switch card {
        case let .insertableParagraph(c):
            return LegalInsertAffordance(
                kind: .body, label: "插入正文", text: c.text, containsPending: c.containsPendingVerification)
        case let .verificationTodos(c):
            return LegalInsertAffordance(
                kind: .verificationTodos, label: "插入待核清单",
                text: Self.formatTodos(c, anchors: anchors), containsPending: true)
        case let .cnkiQuery(c):
            return LegalInsertAffordance(
                kind: .query, label: "插入检索式", text: c.expertQuery, containsPending: false)
        case .evidenceArgumentMatrix, .counterargument, .claimEvidenceMap,
             .nextStepDecisionTree, .fallbackText, .legalAnalysis, .strategyRecommendation,
             .caseFacts, .caseRetrievalReport:
            return nil   // reference / fallback / 作战图(检索式，非上屏正文) → no one-click insert
        }
    }

    /// Section header title for a card.
    public func title(for card: LegalOutputCard) -> String {
        switch card {
        case .evidenceArgumentMatrix: return "证据论证矩阵"
        case .claimEvidenceMap:       return "主张-证据映射"
        case .counterargument:        return "反方观点"
        case .nextStepDecisionTree:   return "下一步决策"
        case .verificationTodos:      return "待核清单"
        case .cnkiQuery:              return "CNKI 检索式"
        case .insertableParagraph:    return "可插入段落"
        case .fallbackText:           return "降级文本"
        case .legalAnalysis:          return "法律分析"
        case .strategyRecommendation: return "策略建议"
        case .caseFacts:              return "检索焦点"
        case .caseRetrievalReport:    return "检索作战图"
        }
    }

    /// Render a `[待核]` checklist: title + one `[待核] <label>` line per resolved anchor.
    public static func formatTodos(_ card: VerificationTodosCard, anchors: [VerificationAnchor]) -> String {
        let byID = Dictionary(anchors.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let lines = card.anchorIds.compactMap { byID[$0] }.map { "[待核] \($0.label)" }
        return ([card.title] + lines).joined(separator: "\n")
    }
}
