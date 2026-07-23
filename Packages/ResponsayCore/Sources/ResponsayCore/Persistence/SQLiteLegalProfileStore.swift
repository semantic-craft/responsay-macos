import Foundation
import SQLite3

/// SQLite-backed `LegalProfileStore` (issue 109). Its own `legal.sqlite` file with
/// two tables — `legal_profiles` (array fields as JSON) and `legal_skill_runs`
/// (no raw text). Open / lock / bind plumbing in `SQLiteConnection`.
public final class SQLiteLegalProfileStore: LegalProfileStore, @unchecked Sendable {
    private let connection: SQLiteConnection

    public init(databaseURL: URL) throws {
        connection = try SQLiteConnection(databaseURL: databaseURL)
        try migrate()
    }

    // MARK: - Profiles

    public func saveProfile(_ profile: LegalPracticeProfile) throws {
        try connection.locked {
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            try connection.prepare("""
            INSERT INTO legal_profiles (
                id, role, primary_domains_json, jurisdictions_json, writing_modes_json,
                citation_preference, source_priority_json, red_lines_json, escalation_matrix_json,
                model_preference, privacy_preference, created_at, updated_at
            ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
            ON CONFLICT(id) DO UPDATE SET
                role = excluded.role,
                primary_domains_json = excluded.primary_domains_json,
                jurisdictions_json = excluded.jurisdictions_json,
                writing_modes_json = excluded.writing_modes_json,
                citation_preference = excluded.citation_preference,
                source_priority_json = excluded.source_priority_json,
                red_lines_json = excluded.red_lines_json,
                escalation_matrix_json = excluded.escalation_matrix_json,
                model_preference = excluded.model_preference,
                privacy_preference = excluded.privacy_preference,
                updated_at = excluded.updated_at;
            """, &statement)

            try connection.bind(profile.id, to: statement, at: 1)
            try connection.bind(profile.role.rawValue, to: statement, at: 2)
            try connection.bind(encode(profile.primaryDomains), to: statement, at: 3)
            try connection.bind(encode(profile.jurisdictions), to: statement, at: 4)
            try connection.bind(encode(profile.writingModes), to: statement, at: 5)
            try connection.bind(profile.citationPreference.rawValue, to: statement, at: 6)
            try connection.bind(encode(profile.sourcePriority), to: statement, at: 7)
            try connection.bind(encode(profile.redLines), to: statement, at: 8)
            try connection.bind(encode(profile.escalationMatrix), to: statement, at: 9)
            try connection.bind(profile.modelPreference.rawValue, to: statement, at: 10)
            try connection.bind(profile.privacyPreference.rawValue, to: statement, at: 11)
            try connection.bind(profile.createdAt, to: statement, at: 12)
            try connection.bind(profile.updatedAt, to: statement, at: 13)

            guard sqlite3_step(statement) == SQLITE_DONE else { throw connection.lastError() }
        }
    }

    public func loadProfile(id: String) throws -> LegalPracticeProfile? {
        try connection.locked {
            try fetchProfiles(where: "WHERE id = ?", limit: 1) { try connection.bind(id, to: $0, at: 1) }.first
        }
    }

    public func currentProfile() throws -> LegalPracticeProfile? {
        try connection.locked { try fetchProfiles(where: "ORDER BY updated_at DESC", limit: 1) { _ in }.first }
    }

    // MARK: - Run log

    public func recordRun(_ run: LegalSkillRun) throws {
        try connection.locked {
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            try connection.prepare("""
            INSERT OR IGNORE INTO legal_skill_runs (
                id, created_at, context_hash, scene, stage, skill_id, model_route
            ) VALUES (?,?,?,?,?,?,?);
            """, &statement)
            try connection.bind(run.id, to: statement, at: 1)
            sqlite3_bind_double(statement, 2, run.createdAt.timeIntervalSince1970)
            try connection.bind(run.contextHash, to: statement, at: 3)
            try connection.bind(run.scene.rawValue, to: statement, at: 4)
            try connection.bind(run.stage.rawValue, to: statement, at: 5)
            try connection.bind(run.skillId, to: statement, at: 6)
            try connection.bind(run.modelRoute.rawValue, to: statement, at: 7)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw connection.lastError() }
        }
    }

    public func recentRuns(_ limit: Int) throws -> [LegalSkillRun] {
        try connection.locked {
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            try connection.prepare("""
            SELECT id, created_at, context_hash, scene, stage, skill_id, model_route
            FROM legal_skill_runs ORDER BY created_at DESC LIMIT ?;
            """, &statement)
            sqlite3_bind_int(statement, 1, Int32(limit))
            var runs: [LegalSkillRun] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                runs.append(LegalSkillRun(
                    id: try connection.columnText(statement, 0),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                    contextHash: try connection.columnText(statement, 2),
                    scene: try decodeEnum(LegalScene.self, statement, 3),
                    stage: try decodeEnum(LegalStage.self, statement, 4),
                    skillId: try connection.columnText(statement, 5),
                    modelRoute: try decodeEnum(ModelRoute.self, statement, 6)))
            }
            return runs
        }
    }

    // MARK: - Migration

    private func migrate() throws {
        try connection.locked {
            try connection.execute("""
            CREATE TABLE IF NOT EXISTS metadata (
                key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL);
            """)
            try connection.execute("""
            CREATE TABLE IF NOT EXISTS legal_profiles (
                id TEXT PRIMARY KEY NOT NULL,
                role TEXT NOT NULL,
                primary_domains_json TEXT NOT NULL,
                jurisdictions_json TEXT NOT NULL,
                writing_modes_json TEXT NOT NULL,
                citation_preference TEXT NOT NULL,
                source_priority_json TEXT NOT NULL,
                red_lines_json TEXT NOT NULL,
                escalation_matrix_json TEXT NOT NULL,
                model_preference TEXT NOT NULL,
                privacy_preference TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL);
            """)
            try connection.execute("""
            CREATE TABLE IF NOT EXISTS legal_skill_runs (
                id TEXT PRIMARY KEY NOT NULL,
                created_at REAL NOT NULL,
                context_hash TEXT NOT NULL,
                scene TEXT NOT NULL,
                stage TEXT NOT NULL,
                skill_id TEXT NOT NULL,
                model_route TEXT NOT NULL);
            """)
            try connection.execute("""
            INSERT INTO metadata (key, value) VALUES ('schema_version', '\(AppSchemaVersion.current)')
            ON CONFLICT(key) DO UPDATE SET value = excluded.value;
            """)
        }
    }

    private func fetchProfiles(
        where clause: String, limit: Int, bind: (OpaquePointer?) throws -> Void
    ) throws -> [LegalPracticeProfile] {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        try connection.prepare("""
        SELECT id, role, primary_domains_json, jurisdictions_json, writing_modes_json,
               citation_preference, source_priority_json, red_lines_json, escalation_matrix_json,
               model_preference, privacy_preference, created_at, updated_at
        FROM legal_profiles \(clause) LIMIT \(limit);
        """, &statement)
        try bind(statement)
        var profiles: [LegalPracticeProfile] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            profiles.append(try decodeProfile(statement))
        }
        return profiles
    }

    private func decodeProfile(_ s: OpaquePointer?) throws -> LegalPracticeProfile {
        LegalPracticeProfile(
            id: try connection.columnText(s, 0),
            role: try decodeEnum(LegalUserRole.self, s, 1),
            primaryDomains: try decode([LegalScene].self, connection.columnText(s, 2)),
            jurisdictions: try decode([String].self, connection.columnText(s, 3)),
            writingModes: try decode([LegalWritingMode].self, connection.columnText(s, 4)),
            citationPreference: try decodeEnum(CitationPreference.self, s, 5),
            sourcePriority: try decode([SourcePreference].self, connection.columnText(s, 6)),
            redLines: try decode([String].self, connection.columnText(s, 7)),
            escalationMatrix: try decode([EscalationRule].self, connection.columnText(s, 8)),
            modelPreference: try decodeEnum(ModelPreference.self, s, 9),
            privacyPreference: try decodeEnum(PrivacyPreference.self, s, 10),
            createdAt: try connection.columnText(s, 11),
            updatedAt: try connection.columnText(s, 12))
    }

    // MARK: - JSON helpers

    private func encode<T: Encodable>(_ value: T) throws -> String {
        try String(data: JSONEncoder().encode(value), encoding: .utf8)
            .ok("Unable to encode \(T.self).")
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func decodeEnum<T: RawRepresentable>(_ type: T.Type, _ s: OpaquePointer?, _ index: Int32) throws -> T
    where T.RawValue == String {
        try T(rawValue: connection.columnText(s, index)).ok("Invalid stored value for \(T.self).")
    }
}

private extension Optional {
    func ok(_ message: String) throws -> Wrapped {
        guard let self else { throw PersistenceError.invalidStoredValue(message) }
        return self
    }
}

public extension LegalProfileStore where Self == SQLiteLegalProfileStore {
    /// The app's default legal store at `<App Support>/<brand>/legal.sqlite`.
    static func defaultStore() throws -> SQLiteLegalProfileStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(AppBrand.appSupportDirectoryName, isDirectory: true)
        return try SQLiteLegalProfileStore(databaseURL: base.appendingPathComponent("legal.sqlite"))
    }
}
