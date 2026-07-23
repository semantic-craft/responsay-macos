import Foundation
import Testing
@testable import ResponsayCore

// 381 — the exact transform type (actionKind) is persisted per capture so History
// filters precisely instead of guessing from `language`.

// MARK: - Model defaults + tolerant decode

@Test func captureItem_defaultsToDictation() {
    let item = CaptureItem(sourceText: "a", language: "en-US", idiomatic: "A.", reasons: [])
    #expect(item.actionKind == .dictation)
}

@Test func captureItem_roundTripsActionKind() throws {
    let item = CaptureItem(sourceText: "x", language: "zh-CN", idiomatic: "y", reasons: [], actionKind: .translate)
    let data = try JSONEncoder().encode(item)
    let decoded = try JSONDecoder().decode(CaptureItem.self, from: data)
    #expect(decoded.actionKind == .translate)
}

@Test func captureItem_oldJSONWithoutActionKind_decodesAsDictation() throws {
    // A captures.json written before the field existed.
    let legacy = """
    {"id":"11111111-1111-1111-1111-111111111111","createdAt":0,"sourceText":"hi",
     "language":"en-US","idiomatic":"Hi.","reasons":[]}
    """
    let decoded = try JSONDecoder().decode(CaptureItem.self, from: Data(legacy.utf8))
    #expect(decoded.actionKind == .dictation)
}

@Test func reviewCard_carriesActionKindFromCapture() {
    let capture = CaptureItem(sourceText: "x", language: "en-US", idiomatic: "y", reasons: [], actionKind: .rewrite)
    let card = ReviewCard(capture: capture)
    #expect(card.actionKind == .rewrite)
    #expect(card.captureItem.actionKind == .rewrite)
}

// MARK: - SQLite persistence + migration

private func tempReviewURL() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("review.sqlite")
}

@Test func sqliteReviewStore_persistsActionKind() throws {
    let url = try tempReviewURL()
    let store = try SQLiteReviewStore(databaseURL: url)
    let card = ReviewCard(sourceText: "x", language: "en-US", idiomatic: "y", reasons: [], actionKind: .coach)
    try store.save(card)
    #expect(try store.recent(1).first?.actionKind == .coach)
}

@Test func sqliteReviewStore_migrationIsIdempotent() throws {
    let url = try tempReviewURL()
    // Opening twice runs migrate() twice; the guarded ALTER must not throw the second time.
    _ = try SQLiteReviewStore(databaseURL: url)
    let store = try SQLiteReviewStore(databaseURL: url)
    let card = ReviewCard(sourceText: "x", language: "en-US", idiomatic: "y", reasons: [], actionKind: .polish)
    try store.save(card)
    #expect(try store.recent(1).first?.actionKind == .polish)
}

@Test func sqliteReviewStore_legacyRowWithoutColumn_readsAsDictation() throws {
    let url = try tempReviewURL()
    // Build a pre-381 table (no action_kind column) and insert one row directly.
    let legacy = try SQLiteConnection(databaseURL: url)
    try legacy.execute("""
    CREATE TABLE review_cards (
        id TEXT PRIMARY KEY NOT NULL, created_at REAL NOT NULL, source_text TEXT NOT NULL,
        language TEXT NOT NULL, idiomatic TEXT NOT NULL, reasons_json TEXT NOT NULL,
        due_at REAL NOT NULL, interval_days INTEGER NOT NULL, repetitions INTEGER NOT NULL,
        ease_factor REAL NOT NULL);
    """)
    try legacy.execute("""
    INSERT INTO review_cards VALUES
    ('99999999-9999-9999-9999-999999999999', 1, 'old', 'en-US', 'Old.', '[]', 1, 0, 0, 2.5);
    """)

    // Opening through SQLiteReviewStore migrates the column in; the old row defaults to dictation.
    let store = try SQLiteReviewStore(databaseURL: url)
    let row = try #require(try store.recent(1).first)
    #expect(row.sourceText == "old")
    #expect(row.actionKind == .dictation)
}

// MARK: - Producer (CaptureTransformer) stamps the right kind

@MainActor
private struct OKRewriter: TextRewriteAPI {
    func rewrite(_ text: String, style: RewriteStyle) async throws -> PolishResult {
        PolishResult(text: "rewritten", original: text, changes: [])
    }
}

@MainActor
private struct OKTranslator: TextTranslationAPI {
    func translate(
        _ text: String,
        target: TranslationTargetLanguage,
        style: TextTranslationStyle
    ) async throws -> TranslationResult {
        TranslationResult(text: "translated", original: text, targetLanguage: target.rawValue, notes: [])
    }
}

@MainActor
private func kindTransformer(
    polisher: (any TextPolishAPI)? = nil,
    rewriter: (any TextRewriteAPI)? = nil,
    translator: (any TextTranslationAPI)? = nil
    ) -> CaptureTransformer {
        CaptureTransformer(
            polisher: polisher, rewriter: rewriter, translator: translator,
            contextProvider: nil, translationTargetProvider: nil,
            rewriteToneProvider: nil, rewriteStyleProvider: nil)
}

private func outcomeItem(_ outcome: TextTransformOutcome) -> CaptureItem? {
    switch outcome {
    case let .insert(_, item), let .review(_, _, item),
         let .autoInsertedReview(_, _, item):
        return item
    case let .failed(_, _, _, item):
        return item
    case .intentInsert, .intentNeedsReview, .intentSafeUnavailable:
        return nil
    }
}

private func itemKind(_ outcome: TextTransformOutcome) -> TextActionKind? {
    outcomeItem(outcome)?.actionKind
}

@Test @MainActor func transformer_raw_stampsDictation() async {
    let item = outcomeItem(await kindTransformer().raw("hi", locale: .english))
    #expect(item?.actionKind == .dictation)
    #expect(item?.sourceText == "hi")
}

@Test @MainActor func transformer_polish_retainsSource() async {
    let item = outcomeItem(await kindTransformer(
        polisher: MockTextPolishAPI(result: PolishResult(text: "Hi.", original: "hi")))
        .polish("hi", locale: .english))
    #expect(item?.actionKind == .polish)
    #expect(item?.sourceText == "hi")
}

@Test @MainActor func transformer_rewrite_stampsRewrite() async {
    let item = outcomeItem(await kindTransformer(rewriter: OKRewriter()).rewrite("x", locale: .chinese))
    #expect(item?.actionKind == .rewrite)
    #expect(item?.sourceText == "x")
}

@Test @MainActor func transformer_translate_stampsTranslate() async {
    let item = outcomeItem(await kindTransformer(translator: OKTranslator())
        .translate("x", preview: false, locale: .chinese))
    #expect(item?.actionKind == .translate)
    #expect(item?.sourceText == "x")
}

@Test @MainActor func transformer_express_stampsCoach() async {
    let coach = MockCoachAPI(result: ExpressionResult(idiomatic: "I see.", original: "我懂了", reasons: []))
    let item = outcomeItem(await kindTransformer().express("我懂了", using: coach, locale: .chinese))
    #expect(item?.actionKind == .coach)
    #expect(item?.sourceText == "我懂了")
}

@Test @MainActor func transformer_rewriteFailure_fallsBackToDictation() async {
    // No rewriter → failure → preserved raw transcript recorded as dictation.
    #expect(itemKind(await kindTransformer().rewrite("x", locale: .chinese)) == .dictation)
}
