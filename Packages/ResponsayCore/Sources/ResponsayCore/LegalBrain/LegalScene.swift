import Foundation

// MARK: - Legal scene / stage taxonomy
//
// Platform-agnostic core taxonomy for the Legal Brain layer (issue 101 / spec
// 2026-06-07-legal-brain-layer). Everything under LegalBrain/ depends on Foundation only —
// no AppKit / ApplicationServices / Carbon / SwiftUI (platform boundary, spec §10).
// Inputs flow in as `ExpressionContext`; outputs flow out as the JSON schemas in this module.

/// Vertical work domain ("现在处于哪类法律工作"). Mirrors the Claude-for-Legal-style
/// practice areas, trimmed to the v0 set plus future placeholders.
public enum LegalScene: String, Codable, Sendable, CaseIterable {
    case litigation
    case academicWriting
    case privacy
    case contract
    case productCompliance
    case unknown
}

/// Stage within a scene ("接案 / 要件分析 / 起草 …"). Used by the scene/stage router
/// (issue 104) to pick candidate skills.
public enum LegalStage: String, Codable, Sendable, CaseIterable {
    case matterIntake
    case claimChart
    case evidenceReview
    case briefDrafting
    case argumentDrafting
    case literatureReview
    case citationDrafting
    case productReview
    case piaTriage
    case trialPreparation
    case initialConsultation
    case caseAssessment
    case pleadingDrafting
    case evidenceExchange
    case postRetrievalSynthesis
    case searchPreparation
    case peerReview
    case unknown
}
