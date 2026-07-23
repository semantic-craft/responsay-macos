import Foundation
import SQLite3

/// Transactional schema migration for the single Review/History store.
///
/// Version 2 rebuilds the v1 table because SQLite cannot remove a column-level
/// `NOT NULL` constraint in place. The copy is committed only after every row and
/// the schema-version write succeed.
struct SQLiteReviewStoreMigration {
    private let connection: SQLiteConnection

    init(connection: SQLiteConnection) {
        self.connection = connection
    }

    func run(_ workAfterSchema: () throws -> Void) throws {
        try connection.execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            try createMetadataTable()
            try createReviewTableIfNeeded()
            try migrateSourceTextIfNeeded()
            try addActionKindIfNeeded()
            try addIntentColumnsIfNeeded()
            try workAfterSchema()
            try recordCurrentVersion()
            try connection.execute("COMMIT;")
        } catch {
            let migrationError = error
            do {
                try connection.execute("ROLLBACK;")
            } catch {
                throw PersistenceError.sqlite(
                    "Review migration failed and rollback failed: \(migrationError); \(error)")
            }
            throw migrationError
        }
    }

    // MARK: - Schema

    private func createMetadataTable() throws {
        try connection.execute("""
        CREATE TABLE IF NOT EXISTS metadata (
            key TEXT PRIMARY KEY NOT NULL,
            value TEXT NOT NULL
        );
        """)
    }

    private func createReviewTableIfNeeded() throws {
        try connection.execute("""
        CREATE TABLE IF NOT EXISTS review_cards (
            id TEXT PRIMARY KEY NOT NULL,
            created_at REAL NOT NULL,
            source_text TEXT,
            language TEXT NOT NULL,
            idiomatic TEXT NOT NULL,
            reasons_json TEXT NOT NULL,
            due_at REAL NOT NULL,
            interval_days INTEGER NOT NULL,
            repetitions INTEGER NOT NULL,
            ease_factor REAL NOT NULL,
            action_kind TEXT NOT NULL DEFAULT 'dictation',
            intent_route TEXT,
            intent_outcome TEXT
        );
        """)
    }

    private func migrateSourceTextIfNeeded() throws {
        guard try columnIsNotNull("source_text") else { return }
        let hasActionKind = try columnExists("action_kind")

        try connection.execute("""
        ALTER TABLE review_cards RENAME TO review_cards_v1;
        """)
        try createReviewTableIfNeeded()
        if hasActionKind {
            try connection.execute("""
            INSERT INTO review_cards (
                id, created_at, source_text, language, idiomatic, reasons_json,
                due_at, interval_days, repetitions, ease_factor, action_kind
            )
            SELECT id, created_at, source_text, language, idiomatic, reasons_json,
                   due_at, interval_days, repetitions, ease_factor, action_kind
            FROM review_cards_v1;
            """)
        } else {
            try connection.execute("""
            INSERT INTO review_cards (
                id, created_at, source_text, language, idiomatic, reasons_json,
                due_at, interval_days, repetitions, ease_factor, action_kind
            )
            SELECT id, created_at, source_text, language, idiomatic, reasons_json,
                   due_at, interval_days, repetitions, ease_factor, 'dictation'
            FROM review_cards_v1;
            """)
        }
        try connection.execute("""
        DROP TABLE review_cards_v1;
        """)
    }

    private func addActionKindIfNeeded() throws {
        guard try !columnExists("action_kind") else { return }
        try connection.execute(
            "ALTER TABLE review_cards ADD COLUMN action_kind TEXT NOT NULL DEFAULT 'dictation';")
    }

    /// v3 (#565): add the nullable Intent-aware route / outcome columns on databases that predate
    /// them. Both are nullable, so a plain `ADD COLUMN` suffices — no table rebuild. Idempotent via
    /// live column inspection, mirroring `addActionKindIfNeeded`.
    private func addIntentColumnsIfNeeded() throws {
        if try !columnExists("intent_route") {
            try connection.execute("ALTER TABLE review_cards ADD COLUMN intent_route TEXT;")
        }
        if try !columnExists("intent_outcome") {
            try connection.execute("ALTER TABLE review_cards ADD COLUMN intent_outcome TEXT;")
        }
    }

    private func recordCurrentVersion() throws {
        try connection.run("""
        INSERT INTO metadata (key, value)
        VALUES ('schema_version', ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value;
        """) { statement in
            try connection.bind(String(AppSchemaVersion.current), to: statement, at: 1)
        }
    }

    // MARK: - Live schema inspection

    private func columnExists(_ column: String) throws -> Bool {
        try columnNotNullFlag(column) != nil
    }

    private func columnIsNotNull(_ column: String) throws -> Bool {
        guard let isNotNull = try columnNotNullFlag(column) else {
            throw PersistenceError.invalidStoredValue("Missing review_cards.\(column) column.")
        }
        return isNotNull
    }

    /// Returns the PRAGMA `notnull` flag for a named column.
    private func columnNotNullFlag(_ column: String) throws -> Bool? {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        try connection.prepare("PRAGMA table_info(review_cards);", &statement)
        while sqlite3_step(statement) == SQLITE_ROW {
            if connection.columnOptionalText(statement, 1) == column {
                return sqlite3_column_int(statement, 3) != 0
            }
        }
        return nil
    }
}
