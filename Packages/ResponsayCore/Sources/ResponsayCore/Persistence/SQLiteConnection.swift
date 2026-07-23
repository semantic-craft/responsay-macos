import Foundation
import SQLite3

/// Shared SQLite connection + prepared-statement plumbing. Was copy-pasted
/// across `SQLiteReviewStore` / `SQLiteHistoryMediaStore` / `SQLiteDrillStore`
/// (brooks-lint R3), then `SQLiteLegalProfileStore` followed; all four stores now
/// own their schema + row mapping and call through this for open / lock / bind /
/// step. Internal to the Persistence layer.
///
/// `FULLMUTEX` + the `NSLock` give the same single-writer guarantee the stores
/// had before. The low-level helpers do NOT lock — only the explicit `locked(_:)`
/// does — so a store may call `run`/`prepare`/`bind` inside one `locked` block
/// without re-entering the lock.
final class SQLiteConnection: @unchecked Sendable {
    let handle: OpaquePointer?
    private let lock = NSLock()

    init(databaseURL: URL) throws {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &db, flags, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open database."
            sqlite3_close(db)
            throw PersistenceError.sqlite(message)
        }
        self.handle = db
    }

    deinit { sqlite3_close(handle) }

    // MARK: Serialization

    func locked<T>(_ work: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        return try work()
    }

    // MARK: Statements

    func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw lastError() }
    }

    func prepare(_ sql: String, _ statement: inout OpaquePointer?) throws {
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw lastError() }
    }

    /// Prepare → bind → step-to-DONE a non-query statement.
    func run(_ sql: String, bind: (OpaquePointer?) throws -> Void) throws {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        try prepare(sql, &statement)
        try bind(statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
    }

    // MARK: Bind

    func bind(_ value: String, to statement: OpaquePointer?, at index: Int32) throws {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(statement, index, value, -1, transient) == SQLITE_OK else { throw lastError() }
    }

    func bindOptional(_ value: String?, to statement: OpaquePointer?, at index: Int32) throws {
        if let value {
            try bind(value, to: statement, at: index)
        } else {
            guard sqlite3_bind_null(statement, index) == SQLITE_OK else { throw lastError() }
        }
    }

    func bindOptional(_ value: Double?, to statement: OpaquePointer?, at index: Int32) {
        if let value {
            sqlite3_bind_double(statement, index, value)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    // MARK: Read columns

    func columnText(_ statement: OpaquePointer?, _ index: Int32) throws -> String {
        guard let text = sqlite3_column_text(statement, index) else {
            throw PersistenceError.invalidStoredValue("Missing text column \(index).")
        }
        return String(cString: text)
    }

    func columnOptionalText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let text = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: text)
    }

    func columnOptionalDouble(_ statement: OpaquePointer?, _ index: Int32) -> Double? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_double(statement, index)
    }

    // MARK: Errors

    func lastError() -> PersistenceError {
        .sqlite(handle.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite error.")
    }
}
