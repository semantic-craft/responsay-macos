import Foundation
import SQLite3
import Testing
@testable import ResponsayCore

private func tempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func sqliteColumnIsNotNull(
    _ column: String,
    table: String,
    databaseURL: URL
) throws -> Bool {
    let connection = try SQLiteConnection(databaseURL: databaseURL)
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    try connection.prepare("PRAGMA table_info(\(table));", &statement)
    while sqlite3_step(statement) == SQLITE_ROW {
        if connection.columnOptionalText(statement, 1) == column {
            return sqlite3_column_int(statement, 3) != 0
        }
    }
    throw PersistenceError.invalidStoredValue("Missing \(table).\(column).")
}

@Test func sqliteReviewStore_migratesEmptyV1Store() throws {
    let directory = try tempDirectory()
    let store = try SQLiteReviewStore(databaseURL: directory.appendingPathComponent("review.sqlite"))

    #expect(try store.schemaVersion() == AppSchemaVersion.current)
    #expect(try store.count() == 0)
    #expect(try store.recent(10).isEmpty)
}

@Test func sqliteReviewStore_importsCapturesWithoutDeletingSource() throws {
    let directory = try tempDirectory()
    let capturesURL = directory.appendingPathComponent("captures.json")
    let old = CaptureItem(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        createdAt: Date(timeIntervalSince1970: 10),
        sourceText: "我想修复这个 bug",
        language: "zh-CN",
        idiomatic: "I want to fix this bug.",
        reasons: ["English needs the infinitive after want."])
    let newer = CaptureItem(
        id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        createdAt: Date(timeIntervalSince1970: 20),
        sourceText: "i want fix bug",
        language: "en-US",
        idiomatic: "I want to fix the bug.",
        reasons: ["Add to before fix."])
    try JSONEncoder().encode([old, newer]).write(to: capturesURL)

    let store = try SQLiteReviewStore(
        databaseURL: directory.appendingPathComponent("review.sqlite"),
        importCapturesFrom: capturesURL)
    let recent = try store.recent(10)

    #expect(try store.count() == 2)
    #expect(recent.map(\.id) == [newer.id, old.id])
    #expect(recent.first?.dueAt == newer.createdAt)
    #expect(recent.first?.reasons == newer.reasons)
    #expect(FileManager.default.fileExists(atPath: capturesURL.path))
}

@Test func sqliteReviewStore_dueReturnsStableCards() throws {
    let directory = try tempDirectory()
    let store = try SQLiteReviewStore(databaseURL: directory.appendingPathComponent("review.sqlite"))
    let due = ReviewCard(
        id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
        createdAt: Date(timeIntervalSince1970: 1),
        sourceText: "a",
        language: "en-US",
        idiomatic: "A.",
        reasons: [],
        dueAt: Date(timeIntervalSince1970: 5))
    let future = ReviewCard(
        createdAt: Date(timeIntervalSince1970: 2),
        sourceText: "b",
        language: "en-US",
        idiomatic: "B.",
        reasons: [],
        dueAt: Date(timeIntervalSince1970: 50))

    try store.save(future)
    try store.save(due)
    let cards = try store.due(now: Date(timeIntervalSince1970: 10), limit: 10)

    #expect(cards.map(\.id) == [due.id])
}

@Test func sqliteReviewStore_freshDatabasePersistsNilSourceAcrossRestart() throws {
    let directory = try tempDirectory()
    let databaseURL = directory.appendingPathComponent("review.sqlite")
    let card = ReviewCard(
        id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
        createdAt: Date(timeIntervalSince1970: 30),
        sourceText: nil,
        language: "zh-CN",
        idiomatic: "获准结果",
        reasons: ["privacy retained final only"],
        actionKind: .translate,
        dueAt: Date(timeIntervalSince1970: 40))

    try SQLiteReviewStore(databaseURL: databaseURL).save(card)
    let reopened = try SQLiteReviewStore(databaseURL: databaseURL)
    let restored = try #require(try reopened.recent(1).first)

    #expect(restored == card)
    #expect(restored.sourceText == nil)
    #expect(try !sqliteColumnIsNotNull("source_text", table: "review_cards", databaseURL: databaseURL))
}

@Test func sqliteReviewStore_migratesV1NotNullSourceWithoutLosingFields() throws {
    let directory = try tempDirectory()
    let databaseURL = directory.appendingPathComponent("review.sqlite")
    let legacy = try SQLiteConnection(databaseURL: databaseURL)
    try legacy.execute("""
    CREATE TABLE metadata (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL);
    INSERT INTO metadata VALUES ('schema_version', '1');
    CREATE TABLE review_cards (
        id TEXT PRIMARY KEY NOT NULL,
        created_at REAL NOT NULL,
        source_text TEXT NOT NULL,
        language TEXT NOT NULL,
        idiomatic TEXT NOT NULL,
        reasons_json TEXT NOT NULL,
        due_at REAL NOT NULL,
        interval_days INTEGER NOT NULL,
        repetitions INTEGER NOT NULL,
        ease_factor REAL NOT NULL,
        action_kind TEXT NOT NULL DEFAULT 'dictation'
    );
    INSERT INTO review_cards VALUES (
        '77777777-7777-7777-7777-777777777777', 10, 'legacy raw', 'en-US',
        'Approved result.', '["legacy reason"]', 20, 9, 4, 2.35, 'translate'
    );
    """)

    let store = try SQLiteReviewStore(databaseURL: databaseURL)
    let migrated = try #require(try store.recent(10).first)
    let nilSource = ReviewCard(
        id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
        createdAt: Date(timeIntervalSince1970: 30),
        sourceText: nil,
        language: "zh-CN",
        idiomatic: "仅保存结果",
        reasons: [],
        actionKind: .coach,
        dueAt: Date(timeIntervalSince1970: 40))
    try store.save(nilSource)
    let rows = try store.recent(10)

    #expect(migrated.id == UUID(uuidString: "77777777-7777-7777-7777-777777777777"))
    #expect(migrated.createdAt == Date(timeIntervalSince1970: 10))
    #expect(migrated.sourceText == "legacy raw")
    #expect(migrated.language == "en-US")
    #expect(migrated.idiomatic == "Approved result.")
    #expect(migrated.reasons == ["legacy reason"])
    #expect(migrated.dueAt == Date(timeIntervalSince1970: 20))
    #expect(migrated.intervalDays == 9)
    #expect(migrated.repetitions == 4)
    #expect(migrated.easeFactor == 2.35)
    #expect(migrated.actionKind == .translate)
    #expect(try store.schemaVersion() == AppSchemaVersion.current)
    #expect(rows.first?.sourceText == nil)
    #expect(rows.count == 2)

    let restarted = try SQLiteReviewStore(databaseURL: databaseURL)
    #expect(try restarted.count() == 2)
    #expect(try restarted.recent(10).first?.sourceText == nil)
    #expect(try !sqliteColumnIsNotNull("source_text", table: "review_cards", databaseURL: databaseURL))
}

@Test func sqliteReviewStore_failedRebuildRollsBackLegacyTableAndVersion() throws {
    let directory = try tempDirectory()
    let databaseURL = directory.appendingPathComponent("review.sqlite")
    let legacy = try SQLiteConnection(databaseURL: databaseURL)
    try legacy.execute("""
    CREATE TABLE metadata (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL);
    INSERT INTO metadata VALUES ('schema_version', '1');
    CREATE TABLE review_cards (
        id TEXT PRIMARY KEY NOT NULL,
        created_at REAL NOT NULL,
        source_text TEXT NOT NULL,
        language TEXT,
        idiomatic TEXT NOT NULL,
        reasons_json TEXT NOT NULL,
        due_at REAL NOT NULL,
        interval_days INTEGER NOT NULL,
        repetitions INTEGER NOT NULL,
        ease_factor REAL NOT NULL,
        action_kind TEXT NOT NULL DEFAULT 'dictation'
    );
    INSERT INTO review_cards VALUES (
        '99999999-9999-9999-9999-999999999999', 1, 'legacy survives', NULL,
        'Approved result.', '[]', 2, 3, 4, 2.2, 'coach'
    );
    """)

    var migrationError: (any Error)?
    do {
        _ = try SQLiteReviewStore(databaseURL: databaseURL)
    } catch {
        migrationError = error
    }
    #expect(migrationError != nil)
    #expect(!String(describing: migrationError).contains("legacy survives"))

    let inspection = try SQLiteConnection(databaseURL: databaseURL)
    var row: OpaquePointer?
    defer { sqlite3_finalize(row) }
    try inspection.prepare(
        "SELECT source_text, action_kind FROM review_cards WHERE id = '99999999-9999-9999-9999-999999999999';",
        &row)
    #expect(sqlite3_step(row) == SQLITE_ROW)
    #expect(try inspection.columnText(row, 0) == "legacy survives")
    #expect(try inspection.columnText(row, 1) == "coach")
    #expect(try sqliteColumnIsNotNull("source_text", table: "review_cards", databaseURL: databaseURL))

    var version: OpaquePointer?
    defer { sqlite3_finalize(version) }
    try inspection.prepare("SELECT value FROM metadata WHERE key = 'schema_version';", &version)
    #expect(sqlite3_step(version) == SQLITE_ROW)
    #expect(try inspection.columnText(version, 0) == "1")
}

@Test func sqliteReviewStore_nilSourceSupportsDueGradeUpdateAndRestart() throws {
    let directory = try tempDirectory()
    let databaseURL = directory.appendingPathComponent("review.sqlite")
    let store = try SQLiteReviewStore(databaseURL: databaseURL)
    let card = ReviewCard(
        sourceText: nil,
        language: "zh-CN",
        idiomatic: "可学习的获准结果",
        reasons: [],
        actionKind: .coach,
        dueAt: Date(timeIntervalSince1970: 1))
    try store.save(card)

    let due = try #require(try store.due(now: Date(timeIntervalSince1970: 2), limit: 10).first)
    let graded = try store.grade(due, grade: .good, reviewedAt: Date(timeIntervalSince1970: 10))
    let restarted = try SQLiteReviewStore(databaseURL: databaseURL)
    let restored = try #require(try restarted.recent(1).first)

    #expect(due.sourceText == nil)
    #expect(graded.sourceText == nil)
    #expect(restored.sourceText == nil)
    #expect(restored.repetitions == 1)
    #expect(restored.intervalDays == 1)
    #expect(restored.dueAt == Date(timeIntervalSince1970: 86_410))
}

@Test func sm2Scheduler_easyReviewAdvancesDueDateAndRepetitions() throws {
    let reviewedAt = Date(timeIntervalSince1970: 100)
    let card = ReviewCard(
        sourceText: "i want fix bug",
        language: "en-US",
        idiomatic: "I want to fix the bug.",
        reasons: [])

    let next = SM2Scheduler.schedule(card, grade: .easy, reviewedAt: reviewedAt)

    #expect(next.repetitions == 1)
    #expect(next.intervalDays == 1)
    #expect(next.dueAt == reviewedAt.addingTimeInterval(86_400))
    #expect(next.easeFactor > card.easeFactor)
}

@Test func sm2Scheduler_failedReviewResetsRepetitions() throws {
    let reviewedAt = Date(timeIntervalSince1970: 200)
    let card = ReviewCard(
        sourceText: "a",
        language: "en-US",
        idiomatic: "A.",
        reasons: [],
        intervalDays: 12,
        repetitions: 4,
        easeFactor: 2.4)

    let next = SM2Scheduler.schedule(card, grade: .wrong, reviewedAt: reviewedAt)

    #expect(next.repetitions == 0)
    #expect(next.intervalDays == 1)
    #expect(next.easeFactor < card.easeFactor)
    #expect(next.masteryStars >= 1)
}

@Test func sqliteReviewStore_gradePersistsSM2State() throws {
    let directory = try tempDirectory()
    let store = try SQLiteReviewStore(databaseURL: directory.appendingPathComponent("review.sqlite"))
    let card = ReviewCard(
        id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
        createdAt: Date(timeIntervalSince1970: 1),
        sourceText: "a",
        language: "en-US",
        idiomatic: "A.",
        reasons: [],
        dueAt: Date(timeIntervalSince1970: 1))
    try store.save(card)

    let updated = try store.grade(card, grade: .good, reviewedAt: Date(timeIntervalSince1970: 10))
    let fetched = try #require(try store.recent(1).first)

    #expect(fetched.id == card.id)
    #expect(fetched.repetitions == updated.repetitions)
    #expect(fetched.intervalDays == 1)
    #expect(fetched.dueAt == Date(timeIntervalSince1970: 10 + 86_400))
}

@Test func sqliteReviewStore_persistsIntentRouteAndOutcomeAcrossRestart() throws {
    let directory = try tempDirectory()
    let databaseURL = directory.appendingPathComponent("review.sqlite")
    let card = ReviewCard(
        id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
        createdAt: Date(timeIntervalSince1970: 30),
        sourceText: nil,                       // 原口述未保存 — the Intent-aware privacy shape
        language: "zh-CN",
        idiomatic: "周四开会",
        reasons: [],
        actionKind: .dictation,
        intentRoute: .intentPlan,
        intentOutcome: .inserted,
        dueAt: Date(timeIntervalSince1970: 40))

    try SQLiteReviewStore(databaseURL: databaseURL).save(card)
    let reopened = try SQLiteReviewStore(databaseURL: databaseURL)
    let restored = try #require(try reopened.recent(1).first)

    #expect(restored == card)
    #expect(restored.sourceText == nil)
    #expect(restored.intentRoute == .intentPlan)
    #expect(restored.intentOutcome == .inserted)
    #expect(try reopened.schemaVersion() == 3)
}

@Test func sqliteReviewStore_migratesV2WithoutIntentColumnsToV3() throws {
    let directory = try tempDirectory()
    let databaseURL = directory.appendingPathComponent("review.sqlite")
    // A v2 database (#557): nullable source_text + action_kind, but NO intent_route / intent_outcome.
    let legacy = try SQLiteConnection(databaseURL: databaseURL)
    try legacy.execute("""
    CREATE TABLE metadata (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL);
    INSERT INTO metadata VALUES ('schema_version', '2');
    CREATE TABLE review_cards (
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
        action_kind TEXT NOT NULL DEFAULT 'dictation'
    );
    INSERT INTO review_cards VALUES (
        'BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB', 10, 'legacy raw', 'en-US',
        'Approved result.', '[]', 20, 3, 2, 2.4, 'dictation'
    );
    """)

    let store = try SQLiteReviewStore(databaseURL: databaseURL)
    let migrated = try #require(try store.recent(10).first)
    // A new Intent-aware approved final persists its route + outcome on the upgraded schema.
    try store.save(ReviewCard(
        id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
        createdAt: Date(timeIntervalSince1970: 30),
        sourceText: nil,
        language: "zh-CN",
        idiomatic: "只保存获准结果",
        reasons: [],
        intentRoute: .ordinaryPolished,
        intentOutcome: .copied,
        dueAt: Date(timeIntervalSince1970: 30)))
    let fresh = try #require(try store.recent(1).first)

    #expect(migrated.id == UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"))
    #expect(migrated.intentRoute == nil)              // old rows decode as nil, not a crash
    #expect(migrated.intentOutcome == nil)
    #expect(migrated.sourceText == "legacy raw")
    #expect(fresh.intentRoute == .ordinaryPolished)
    #expect(fresh.intentOutcome == .copied)
    #expect(try store.schemaVersion() == 3)

    let restarted = try SQLiteReviewStore(databaseURL: databaseURL)   // idempotent: re-open is a no-op
    #expect(try restarted.count() == 2)
    #expect(try restarted.recent(1).first?.intentOutcome == .copied)
}

@Test func reviewCaptureStoreWritesCaptureItemsIntoReviewStore() throws {
    let directory = try tempDirectory()
    let reviewStore = try SQLiteReviewStore(databaseURL: directory.appendingPathComponent("review.sqlite"))
    let captureStore = ReviewCaptureStore(reviewStore: reviewStore)
    let capture = CaptureItem(
        id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
        createdAt: Date(timeIntervalSince1970: 30),
        sourceText: "我想修复这个 bug",
        language: "zh-CN",
        idiomatic: "I want to fix this bug.",
        reasons: ["Natural infinitive."])

    try captureStore.save(capture)

    #expect(try reviewStore.count() == 1)
    #expect(try captureStore.recent(1).first == capture)
}

@Test func overviewMetricsAggregateAllRetainedRowsBeyondHistoryPageSize() throws {
    let directory = try tempDirectory()
    let store = try SQLiteReviewStore(
        databaseURL: directory.appendingPathComponent("review.sqlite"))
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    for index in 0..<501 {
        try store.save(ReviewCard(
            createdAt: now.addingTimeInterval(Double(index)),
            sourceText: nil,
            language: "zh-CN",
            idiomatic: "字",
            reasons: []))
    }

    let metrics = try store.overviewMetrics(
        now: now,
        calendar: Calendar(identifier: .gregorian),
        status: .unknown,
        typingCharsPerSecond: 1)

    #expect(metrics.totalSegmentCount == 501)
    #expect(metrics.estimatedTypingSecondsSaved == 501)
}
