import Testing
import Foundation
@testable import ResponsayCore

/// 109 — SQLiteLegalProfileStore: write/read/relaunch/upsert + privacy-safe run log.
struct LegalProfileStoreTests {
    private func tempStore() throws -> (SQLiteLegalProfileStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("legal.sqlite")
        return (try SQLiteLegalProfileStore(databaseURL: url), url)
    }

    private func sampleProfile(id: String = "default") -> LegalPracticeProfile {
        LegalColdStart().defaultProfile(
            id: id, role: .legalScholar, primaryDomains: [.academicWriting, .privacy],
            jurisdictions: ["CN", "EU"], now: "2026-06-07T00:00:00Z")
    }

    @Test func coldStartWrites_relaunchLoads() throws {
        let (store, url) = try tempStore()
        try store.saveProfile(sampleProfile())

        // Relaunch: a fresh store on the same file must load the persisted profile.
        let reopened = try SQLiteLegalProfileStore(databaseURL: url)
        let loaded = try #require(try reopened.currentProfile())
        #expect(loaded.id == "default")
        #expect(loaded.role == .legalScholar)
        #expect(loaded.primaryDomains == [.academicWriting, .privacy])
        #expect(loaded.jurisdictions == ["CN", "EU"])
        #expect(loaded.citationPreference == .legalCitationDraft)
        #expect(loaded.sourcePriority.contains(.cnki))
    }

    @Test func saveProfile_upsertsInPlace() throws {
        let (store, _) = try tempStore()
        try store.saveProfile(sampleProfile())
        let changed = LegalPracticeProfile(
            id: "default", role: .practitioner, primaryDomains: [.litigation], jurisdictions: ["CN"],
            writingModes: [.litigationBrief], citationPreference: .plainFootnote, sourcePriority: [.govLaw],
            redLines: [], escalationMatrix: [], modelPreference: .askEachTime,
            privacyPreference: .selectedTextOnly, createdAt: "2026-06-07T00:00:00Z",
            updatedAt: "2026-06-08T00:00:00Z")
        try store.saveProfile(changed)

        let loaded = try #require(try store.loadProfile(id: "default"))
        #expect(loaded.role == .practitioner)            // upserted, not duplicated
        #expect(loaded.updatedAt == "2026-06-08T00:00:00Z")
    }

    @Test func runLog_storesMetadataNotRawText() throws {
        let (store, _) = try tempStore()
        try store.recordRun(LegalSkillRun(
            id: "run1", createdAt: Date(timeIntervalSince1970: 100), contextHash: "sha256:abcd",
            scene: .litigation, stage: .briefDrafting,
            skillId: "practice.evidence_review.cn", modelRoute: .cloudAllowed))

        let runs = try store.recentRuns(10)
        #expect(runs.count == 1)
        #expect(runs.first?.contextHash == "sha256:abcd")   // hash, never the text
        #expect(runs.first?.scene == .litigation)
        #expect(runs.first?.skillId == "practice.evidence_review.cn")
        #expect(runs.first?.modelRoute == .cloudAllowed)
    }

    @Test func currentProfile_nilWhenEmpty() throws {
        let (store, _) = try tempStore()
        #expect(try store.currentProfile() == nil)
        #expect(try store.recentRuns(5).isEmpty)
    }
}
