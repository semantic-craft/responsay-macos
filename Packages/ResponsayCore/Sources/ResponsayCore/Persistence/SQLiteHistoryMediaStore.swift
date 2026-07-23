import Foundation
import SQLite3

/// SQLite-backed `HistoryMediaStore`: one `history_items` table for metadata,
/// plus an owned `audioDirectory` for the audio files. Schema + row mapping
/// here; open / lock / bind plumbing in `SQLiteConnection`. Spec §6.2.2.
public final class SQLiteHistoryMediaStore: HistoryMediaStore, @unchecked Sendable {
    public let audioDirectory: URL
    private let connection: SQLiteConnection

    public init(databaseURL: URL, audioDirectory: URL) throws {
        self.audioDirectory = audioDirectory
        try FileManager.default.createDirectory(
            at: audioDirectory, withIntermediateDirectories: true)
        connection = try SQLiteConnection(databaseURL: databaseURL)
        try migrate()
    }

    // MARK: Write

    public func save(_ item: HistoryItem) throws {
        try connection.locked { try insert(item) }
    }

    public func delete(id: UUID) throws {
        try connection.locked {
            let filename = try audioFilename(forID: id)
            try connection.run("DELETE FROM history_items WHERE id = ?;") { statement in
                try self.connection.bind(id.uuidString, to: statement, at: 1)
            }
            removeAudio(filename)
        }
    }

    public func deleteAll() throws {
        try connection.locked {
            try connection.execute("DELETE FROM history_items;")
            let files = (try? FileManager.default.contentsOfDirectory(
                at: audioDirectory, includingPropertiesForKeys: nil)) ?? []
            for file in files { try? FileManager.default.removeItem(at: file) }
        }
    }

    @discardableResult
    public func prune(olderThan cutoff: Date) throws -> Int {
        try connection.locked {
            let doomed = try fetchFilenames(
                sql: "SELECT id, audio_filename FROM history_items WHERE created_at < ?;",
                bind: { sqlite3_bind_double($0, 1, cutoff.timeIntervalSince1970) })
            try connection.run("DELETE FROM history_items WHERE created_at < ?;") { statement in
                sqlite3_bind_double(statement, 1, cutoff.timeIntervalSince1970)
            }
            for filename in doomed { removeAudio(filename) }
            return doomed.count
        }
    }

    @discardableResult
    public func cleanupOrphans() throws -> [URL] {
        try connection.locked {
            let referenced = Set(try fetchFilenames(
                sql: "SELECT id, audio_filename FROM history_items;", bind: { _ in }))
            let onDisk = (try? FileManager.default.contentsOfDirectory(
                at: audioDirectory, includingPropertiesForKeys: nil)) ?? []
            var removed: [URL] = []
            for file in onDisk where !referenced.contains(file.lastPathComponent) {
                try? FileManager.default.removeItem(at: file)
                removed.append(file)
            }
            return removed
        }
    }

    // MARK: Read

    public func recent(_ limit: Int) throws -> [HistoryItem] {
        try connection.locked {
            try fetchItems(
                sql: "\(selectColumns) ORDER BY created_at DESC LIMIT ?;",
                bind: { sqlite3_bind_int($0, 1, Int32(limit)) })
        }
    }

    public func item(id: UUID) throws -> HistoryItem? {
        try connection.locked {
            try fetchItems(
                sql: "\(selectColumns) WHERE id = ? LIMIT 1;",
                bind: { try self.connection.bind(id.uuidString, to: $0, at: 1) }).first
        }
    }

    // MARK: Migration

    private func migrate() throws {
        try connection.locked {
            try connection.execute("""
            CREATE TABLE IF NOT EXISTS history_items (
                id TEXT PRIMARY KEY NOT NULL,
                created_at REAL NOT NULL,
                source_app_name TEXT,
                source_bundle_id TEXT,
                action_kind TEXT NOT NULL,
                transcript TEXT,
                result_text TEXT,
                audio_filename TEXT,
                duration REAL,
                provider_summary TEXT,
                privacy_mode TEXT NOT NULL
            );
            """)
            try connection.execute(
                "CREATE INDEX IF NOT EXISTS idx_history_created_at ON history_items(created_at);")
        }
    }

    // MARK: Statements

    private let selectColumns = """
    SELECT id, created_at, source_app_name, source_bundle_id, action_kind,
           transcript, result_text, audio_filename, duration, provider_summary, privacy_mode
    FROM history_items
    """

    private func insert(_ item: HistoryItem) throws {
        try connection.run("""
        INSERT OR REPLACE INTO history_items (
            id, created_at, source_app_name, source_bundle_id, action_kind,
            transcript, result_text, audio_filename, duration, provider_summary, privacy_mode
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """) { statement in
            try self.connection.bind(item.id.uuidString, to: statement, at: 1)
            sqlite3_bind_double(statement, 2, item.createdAt.timeIntervalSince1970)
            try self.connection.bindOptional(item.sourceAppName, to: statement, at: 3)
            try self.connection.bindOptional(item.sourceBundleID, to: statement, at: 4)
            try self.connection.bind(item.actionKind.rawValue, to: statement, at: 5)
            try self.connection.bindOptional(item.transcript, to: statement, at: 6)
            try self.connection.bindOptional(item.resultText, to: statement, at: 7)
            try self.connection.bindOptional(item.audioFileURL?.lastPathComponent, to: statement, at: 8)
            self.connection.bindOptional(item.duration, to: statement, at: 9)
            try self.connection.bindOptional(item.providerSummary, to: statement, at: 10)
            try self.connection.bind(item.privacyMode.rawValue, to: statement, at: 11)
        }
    }

    private func fetchItems(
        sql: String, bind: (OpaquePointer?) throws -> Void
    ) throws -> [HistoryItem] {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        try connection.prepare(sql, &statement)
        try bind(statement)

        var items: [HistoryItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            items.append(try decode(from: statement))
        }
        return items
    }

    private func fetchFilenames(
        sql: String, bind: (OpaquePointer?) -> Void
    ) throws -> [String] {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        try connection.prepare(sql, &statement)
        bind(statement)

        var names: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = connection.columnOptionalText(statement, 1) { names.append(name) }
        }
        return names
    }

    private func audioFilename(forID id: UUID) throws -> String? {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        try connection.prepare("SELECT audio_filename FROM history_items WHERE id = ?;", &statement)
        try connection.bind(id.uuidString, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return connection.columnOptionalText(statement, 0)
    }

    private func decode(from statement: OpaquePointer?) throws -> HistoryItem {
        let id = try UUID(uuidString: try connection.columnText(statement, 0))
            .ok("Invalid history item id.")
        let audioFilename = connection.columnOptionalText(statement, 7)
        return HistoryItem(
            id: id,
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
            sourceAppName: connection.columnOptionalText(statement, 2),
            sourceBundleID: connection.columnOptionalText(statement, 3),
            actionKind: TextActionKind(rawValue: try connection.columnText(statement, 4)) ?? .other,
            transcript: connection.columnOptionalText(statement, 5),
            resultText: connection.columnOptionalText(statement, 6),
            audioFileURL: audioFilename.map { audioDirectory.appendingPathComponent($0) },
            duration: connection.columnOptionalDouble(statement, 8),
            providerSummary: connection.columnOptionalText(statement, 9),
            privacyMode: RoutePrivacyMode(rawValue: try connection.columnText(statement, 10)) ?? .unknown)
    }

    // MARK: Audio files

    private func removeAudio(_ filename: String?) {
        guard let filename, !filename.isEmpty else { return }
        try? FileManager.default.removeItem(at: audioDirectory.appendingPathComponent(filename))
    }
}

private extension Optional {
    func ok(_ message: String) throws -> Wrapped {
        guard let self else { throw PersistenceError.invalidStoredValue(message) }
        return self
    }
}

public extension HistoryMediaStore where Self == SQLiteHistoryMediaStore {
    /// App-default store: `history.sqlite` + `history-audio/` under Application
    /// Support/Responsay.
    static func defaultStore() throws -> SQLiteHistoryMediaStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(AppBrand.appSupportDirectoryName, isDirectory: true)
        return try SQLiteHistoryMediaStore(
            databaseURL: base.appendingPathComponent("history.sqlite"),
            audioDirectory: base.appendingPathComponent("history-audio", isDirectory: true))
    }
}
