import Testing
@testable import ResponsayCore

/// 109 — LegalColdStart defaults + the minimal injectable subset (106 boundary).
struct LegalColdStartTests {
    private let coldStart = LegalColdStart()

    @Test func legalScholar_defaults() {
        let p = coldStart.defaultProfile(id: "x", role: .legalScholar, primaryDomains: [.academicWriting], now: "t")
        #expect(p.citationPreference == .legalCitationDraft)
        #expect(p.writingModes == [.academicArticle])
        #expect(p.sourcePriority.first == .cnki)
        #expect(p.privacyPreference == .selectedTextOnly)   // most private by default
        #expect(p.jurisdictions == ["CN"])
    }

    @Test func litigator_defaults() {
        let p = coldStart.defaultProfile(id: "x", role: .practitioner, primaryDomains: [.litigation], now: "t")
        #expect(p.writingModes == [.litigationBrief, .legalMemo, .contractReview])
        #expect(p.citationPreference == .plainFootnote)
        #expect(p.sourcePriority.contains(.pkulaw))
    }

    @Test func explicitModesOverrideDefaults() {
        let p = coldStart.defaultProfile(
            id: "x", role: .legalScholar, primaryDomains: [], writingModes: [.legalMemo], now: "t")
        #expect(p.writingModes == [.legalMemo])
    }

    @Test func minimalSubset_carriesOnlyInjectableFields() {
        let p = LegalPracticeProfile(
            id: "x", role: .practitioner, primaryDomains: [.privacy], jurisdictions: ["CN"],
            writingModes: [.productReview], citationPreference: .bluebook, sourcePriority: [.govLaw],
            redLines: ["不得涉及客户秘密"],
            escalationMatrix: [EscalationRule(id: "e", condition: "涉及出境", action: "本地模型")],
            modelPreference: .localFirst, privacyPreference: .selectedTextOnly,
            createdAt: "t", updatedAt: "t")
        let subset = p.minimalSubset
        #expect(subset.role == .practitioner)
        #expect(subset.citationPreference == .bluebook)
        #expect(subset.modelPreference == .localFirst)
        #expect(subset.jurisdictions == ["CN"])
        // The subset type structurally has no redLines / escalationMatrix / sourcePriority /
        // privacyPreference fields — they can never reach a prompt.
    }
}
