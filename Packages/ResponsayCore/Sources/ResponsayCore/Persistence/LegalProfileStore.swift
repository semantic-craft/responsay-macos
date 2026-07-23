import Foundation

// MARK: - 109 LegalProfileStore
//
// Persists one default `LegalPracticeProfile` + a privacy-safe `LegalSkillRun` log.
// Protocol so the router (104) / prompt assembler (106) can depend on an abstraction;
// the SQLite impl is parallel to `SQLiteReviewStore` (issue 040).

public protocol LegalProfileStore: Sendable {
    /// Upsert a profile (v0 keeps a single default profile, but keyed by id).
    func saveProfile(_ profile: LegalPracticeProfile) throws
    /// Load a profile by id.
    func loadProfile(id: String) throws -> LegalPracticeProfile?
    /// The most-recently-updated profile (the v0 "current" default), if any.
    func currentProfile() throws -> LegalPracticeProfile?
    /// Append a privacy-safe run-log row (hash/scene/skill/route — never raw text).
    func recordRun(_ run: LegalSkillRun) throws
    /// Most recent run-log rows, newest first.
    func recentRuns(_ limit: Int) throws -> [LegalSkillRun]
}
