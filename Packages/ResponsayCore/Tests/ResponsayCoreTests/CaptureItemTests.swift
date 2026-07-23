import Testing
import Foundation
@testable import ResponsayCore

@Test func captureItem_codableRoundTrip() throws {
    let item = CaptureItem(
        sourceText: "i want fix this bug",
        language: "en-US",
        idiomatic: "I want to fix this bug.",
        reasons: ["缺少不定式 to", "want 后接 to-infinitive"]
    )
    let data = try JSONEncoder().encode(item)
    let decoded = try JSONDecoder().decode(CaptureItem.self, from: data)
    #expect(decoded.sourceText == item.sourceText)
    #expect(decoded.idiomatic == item.idiomatic)
    #expect(decoded.reasons == item.reasons)
    #expect(decoded.id == item.id)
}

@Test func captureItem_missingAndNullSourceDecodeAsNil() throws {
    let legacySource = """
    {"id":"00000000-0000-0000-0000-000000000000","createdAt":0,"sourceText":"  exact source  ",
     "language":"en-US","idiomatic":"Approved result.","reasons":[]}
    """
    let missingSource = """
    {"id":"11111111-1111-1111-1111-111111111111","createdAt":0,
     "language":"en-US","idiomatic":"Approved result.","reasons":[]}
    """
    let nullSource = """
    {"id":"22222222-2222-2222-2222-222222222222","createdAt":0,"sourceText":null,
     "language":"en-US","idiomatic":"Approved result.","reasons":[]}
    """

    let legacy = try JSONDecoder().decode(CaptureItem.self, from: Data(legacySource.utf8))
    let missing = try JSONDecoder().decode(CaptureItem.self, from: Data(missingSource.utf8))
    let explicitNull = try JSONDecoder().decode(CaptureItem.self, from: Data(nullSource.utf8))

    #expect(legacy.sourceText == "  exact source  ")
    #expect(missing.sourceText == nil)
    #expect(explicitNull.sourceText == nil)
}

@Test func captureItem_nilSourceEncodesAndRoundTripsWithoutFallback() throws {
    let item = CaptureItem(
        sourceText: nil,
        language: "zh-CN",
        idiomatic: "获准结果",
        reasons: [])

    let data = try JSONEncoder().encode(item)
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let decoded = try JSONDecoder().decode(CaptureItem.self, from: data)

    #expect(object["sourceText"] == nil || object["sourceText"] is NSNull)
    #expect(decoded.sourceText == nil)
    #expect(decoded.idiomatic == "获准结果")
}

@Test func reviewCard_optionalSourceCodableAndSchedulingPreserveNil() throws {
    let legacySource = """
    {"id":"44444444-4444-4444-4444-444444444444","createdAt":0,"sourceText":"  old raw  ",
     "language":"en-US","idiomatic":"Approved result.","reasons":[],
     "dueAt":0,"intervalDays":3,"repetitions":2,"easeFactor":2.4}
    """
    let missingSource = """
    {"id":"33333333-3333-3333-3333-333333333333","createdAt":0,
     "language":"en-US","idiomatic":"Approved result.","reasons":[],
     "dueAt":0,"intervalDays":3,"repetitions":2,"easeFactor":2.4}
    """
    let nullSource = """
    {"id":"55555555-5555-5555-5555-555555555555","createdAt":0,"sourceText":null,
     "language":"en-US","idiomatic":"Approved result.","reasons":[],
     "dueAt":0,"intervalDays":3,"repetitions":2,"easeFactor":2.4}
    """
    let legacy = try JSONDecoder().decode(ReviewCard.self, from: Data(legacySource.utf8))
    let decoded = try JSONDecoder().decode(ReviewCard.self, from: Data(missingSource.utf8))
    let explicitNull = try JSONDecoder().decode(ReviewCard.self, from: Data(nullSource.utf8))
    let scheduled = decoded.scheduled(
        dueAt: Date(timeIntervalSince1970: 99),
        intervalDays: 6,
        repetitions: 3,
        easeFactor: 2.5)
    let capture = scheduled.captureItem
    let restored = ReviewCard(capture: capture)

    #expect(legacy.sourceText == "  old raw  ")
    #expect(decoded.sourceText == nil)
    #expect(explicitNull.sourceText == nil)
    #expect(scheduled.sourceText == nil)
    #expect(capture.sourceText == nil)
    #expect(restored.sourceText == nil)
    #expect(restored.idiomatic == "Approved result.")
}

@Test func captureItem_intentRouteAndOutcomeRoundTripAndDefaultNil() throws {
    let intent = CaptureItem(
        sourceText: nil,
        language: "zh-CN",
        idiomatic: "周四开会",
        reasons: [],
        intentRoute: .intentPlan,
        intentOutcome: .inserted)
    let plain = CaptureItem(sourceText: "hi", language: "en-US", idiomatic: "Hi.", reasons: [])

    let intentDecoded = try JSONDecoder().decode(CaptureItem.self, from: JSONEncoder().encode(intent))
    let plainDecoded = try JSONDecoder().decode(CaptureItem.self, from: JSONEncoder().encode(plain))

    #expect(intentDecoded.intentRoute == .intentPlan)
    #expect(intentDecoded.intentOutcome == .inserted)
    #expect(intentDecoded.sourceText == nil)
    #expect(plainDecoded.intentRoute == nil)          // non-intent captures carry neither field
    #expect(plainDecoded.intentOutcome == nil)
}

@Test func captureItem_legacyJSONWithoutIntentFieldsDecodesNil() throws {
    // A record written before #565 has no intent_route / intent_outcome keys at all.
    let legacy = """
    {"id":"00000000-0000-0000-0000-000000000000","createdAt":0,"sourceText":"raw",
     "language":"en-US","idiomatic":"Approved result.","reasons":[],"actionKind":"dictation"}
    """
    let decoded = try JSONDecoder().decode(CaptureItem.self, from: Data(legacy.utf8))
    #expect(decoded.intentRoute == nil)
    #expect(decoded.intentOutcome == nil)
    #expect(decoded.sourceText == "raw")
}

@Test func reviewCard_intentFieldsRoundTripAndBridgePreserves() throws {
    let card = ReviewCard(
        sourceText: nil,
        language: "zh-CN",
        idiomatic: "获准结果",
        reasons: [],
        intentRoute: .ordinaryPolished,
        intentOutcome: .copied)

    let decoded = try JSONDecoder().decode(ReviewCard.self, from: JSONEncoder().encode(card))
    let capture = decoded.captureItem
    let restored = ReviewCard(capture: capture)

    #expect(decoded.intentRoute == .ordinaryPolished)
    #expect(decoded.intentOutcome == .copied)
    #expect(capture.intentRoute == .ordinaryPolished)   // bridge CaptureItem preserves both
    #expect(capture.intentOutcome == .copied)
    #expect(restored.intentRoute == .ordinaryPolished)  // and round-trips back into a card
    #expect(restored.intentOutcome == .copied)
}

@Test func historyItem_intentBadgeShowsRouteAndOutcomeOrNil() {
    #expect(HistoryItem(actionKind: .dictation, privacyMode: .unknown).intentBadge == nil)
    #expect(HistoryItem(actionKind: .dictation, privacyMode: .unknown,
                        intentRoute: .intentPlan, intentOutcome: .inserted).intentBadge == "校验成稿 · 已插入")
    #expect(HistoryItem(actionKind: .dictation, privacyMode: .unknown,
                        intentRoute: .ordinaryPolished, intentOutcome: .copied).intentBadge == "普通整理 · 已复制")
}

@Test func expressionResult_decodesBackendShape() throws {
    let json = """
    {"idiomatic":"I want to fix this bug.","original":"i want fix this bug","reasons":["缺 to"]}
    """.data(using: .utf8)!
    let r = try JSONDecoder().decode(ExpressionResult.self, from: json)
    #expect(r.idiomatic == "I want to fix this bug.")
    #expect(r.original == "i want fix this bug")
    #expect(r.reasons == ["缺 to"])
}
