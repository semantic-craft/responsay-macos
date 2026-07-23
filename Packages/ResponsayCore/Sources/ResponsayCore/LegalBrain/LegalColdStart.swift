import Foundation

// MARK: - 109 Cold-start profile builder
//
// The deterministic core of the ≤2-minute Q&A: a few answers (role + domains +
// jurisdictions + modes) → one default `LegalPracticeProfile` with sensible,
// role-aware defaults. No seed-document upload in v0. The Settings UI gathers the
// answers and calls this; `now` is injected (no Date() in core).

public struct LegalColdStart: Sendable {
    public init() {}

    public func defaultProfile(
        id: String,
        role: LegalUserRole,
        primaryDomains: [LegalScene],
        jurisdictions: [String] = ["CN"],
        writingModes: [LegalWritingMode] = [],
        modelPreference: ModelPreference = .askEachTime,
        privacyPreference: PrivacyPreference = .selectedTextOnly,
        now: String
    ) -> LegalPracticeProfile {
        LegalPracticeProfile(
            id: id,
            role: role,
            primaryDomains: primaryDomains,
            jurisdictions: jurisdictions,
            writingModes: writingModes.isEmpty ? Self.defaultModes(for: role) : writingModes,
            citationPreference: Self.defaultCitation(for: role),
            sourcePriority: Self.defaultSources(for: role),
            redLines: [],
            escalationMatrix: [],
            modelPreference: modelPreference,
            privacyPreference: privacyPreference,   // default = most private
            createdAt: now,
            updatedAt: now)
    }

    static func defaultCitation(for role: LegalUserRole) -> CitationPreference {
        switch role {
        case .legalScholar, .student:        return .legalCitationDraft
        case .practitioner:                  return .plainFootnote
        }
    }

    static func defaultModes(for role: LegalUserRole) -> [LegalWritingMode] {
        switch role {
        case .legalScholar, .student:  return [.academicArticle]
        case .practitioner:            return [.litigationBrief, .legalMemo, .contractReview]
        }
    }

    static func defaultSources(for role: LegalUserRole) -> [SourcePreference] {
        switch role {
        case .legalScholar, .student:  return [.cnki, .baiduScholar, .govLaw]
        case .practitioner:            return [.govLaw, .pkulaw]
        }
    }
}
