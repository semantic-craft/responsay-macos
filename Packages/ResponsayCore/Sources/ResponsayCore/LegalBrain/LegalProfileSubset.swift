import Foundation

// MARK: - 109 Minimal injectable profile subset
//
// The ONLY profile fields a model call may see (spec §9): role / domain / jurisdiction
// / writing mode / citation preference / model preference. Deliberately excludes
// redLines, escalationMatrix, sourcePriority, privacyPreference, ids and timestamps —
// those steer routing/privacy locally and must never be sent to a model.

public struct LegalProfileSubset: Sendable, Equatable {
    public let role: LegalUserRole
    public let primaryDomains: [LegalScene]
    public let jurisdictions: [String]
    public let writingModes: [LegalWritingMode]
    public let citationPreference: CitationPreference
    public let modelPreference: ModelPreference

    public init(
        role: LegalUserRole,
        primaryDomains: [LegalScene],
        jurisdictions: [String],
        writingModes: [LegalWritingMode],
        citationPreference: CitationPreference,
        modelPreference: ModelPreference
    ) {
        self.role = role
        self.primaryDomains = primaryDomains
        self.jurisdictions = jurisdictions
        self.writingModes = writingModes
        self.citationPreference = citationPreference
        self.modelPreference = modelPreference
    }
}

public extension LegalPracticeProfile {
    /// The minimal subset safe to inject into a prompt (106).
    var minimalSubset: LegalProfileSubset {
        LegalProfileSubset(
            role: role,
            primaryDomains: primaryDomains,
            jurisdictions: jurisdictions,
            writingModes: writingModes,
            citationPreference: citationPreference,
            modelPreference: modelPreference)
    }
}
