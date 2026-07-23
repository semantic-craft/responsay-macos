import Foundation

public struct ReviewCard: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let createdAt: Date
    /// `nil` means the original utterance was intentionally not retained.
    public let sourceText: String?
    public let language: String
    public let idiomatic: String
    public let reasons: [String]
    /// Which text action produced this card (381) — carried from `CaptureItem` so History
    /// filters exactly. Old rows (no column) read as `.dictation`.
    public let actionKind: TextActionKind
    /// The Intent-aware compile route (校验成稿 / 普通整理) carried from `CaptureItem`, or `nil` for
    /// non-intent cards. Old rows (no column) read as `nil` (#565).
    public let intentRoute: IntentInsertRoute?
    /// The coarse Intent-aware terminal disposition (`inserted` / `copied`), or `nil` for non-intent
    /// cards. Content-free.
    public let intentOutcome: IntentHistoryOutcome?
    public let dueAt: Date
    public let intervalDays: Int
    public let repetitions: Int
    public let easeFactor: Double

    public var masteryStars: Int {
        MasteryStars.rating(repetitions: repetitions, easeFactor: easeFactor)
    }

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        sourceText: String?,
        language: String,
        idiomatic: String,
        reasons: [String],
        actionKind: TextActionKind = .dictation,
        intentRoute: IntentInsertRoute? = nil,
        intentOutcome: IntentHistoryOutcome? = nil,
        dueAt: Date = Date(),
        intervalDays: Int = 0,
        repetitions: Int = 0,
        easeFactor: Double = 2.5
    ) {
        self.id = id
        self.createdAt = createdAt
        self.sourceText = sourceText
        self.language = language
        self.idiomatic = idiomatic
        self.reasons = reasons
        self.actionKind = actionKind
        self.intentRoute = intentRoute
        self.intentOutcome = intentOutcome
        self.dueAt = dueAt
        self.intervalDays = intervalDays
        self.repetitions = repetitions
        self.easeFactor = easeFactor
    }

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, sourceText, language, idiomatic, reasons, actionKind
        case intentRoute, intentOutcome
        case dueAt, intervalDays, repetitions, easeFactor
    }

    /// Tolerant decode preserves legacy source strings while accepting a missing or
    /// explicit-null source. `actionKind` still defaults for old records; `intentRoute` /
    /// `intentOutcome` decode as `nil` on rows that predate them.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        sourceText = try c.decodeIfPresent(String.self, forKey: .sourceText)
        language = try c.decode(String.self, forKey: .language)
        idiomatic = try c.decode(String.self, forKey: .idiomatic)
        reasons = try c.decode([String].self, forKey: .reasons)
        actionKind = try c.decodeIfPresent(TextActionKind.self, forKey: .actionKind) ?? .dictation
        intentRoute = try c.decodeIfPresent(IntentInsertRoute.self, forKey: .intentRoute)
        intentOutcome = try c.decodeIfPresent(IntentHistoryOutcome.self, forKey: .intentOutcome)
        dueAt = try c.decode(Date.self, forKey: .dueAt)
        intervalDays = try c.decode(Int.self, forKey: .intervalDays)
        repetitions = try c.decode(Int.self, forKey: .repetitions)
        easeFactor = try c.decode(Double.self, forKey: .easeFactor)
    }

    public init(capture: CaptureItem) {
        self.init(
            id: capture.id,
            createdAt: capture.createdAt,
            sourceText: capture.sourceText,
            language: capture.language,
            idiomatic: capture.idiomatic,
            reasons: capture.reasons,
            actionKind: capture.actionKind,
            intentRoute: capture.intentRoute,
            intentOutcome: capture.intentOutcome,
            dueAt: capture.createdAt)
    }

    public func scheduled(
        dueAt: Date,
        intervalDays: Int,
        repetitions: Int,
        easeFactor: Double
    ) -> ReviewCard {
        ReviewCard(
            id: id,
            createdAt: createdAt,
            sourceText: sourceText,
            language: language,
            idiomatic: idiomatic,
            reasons: reasons,
            actionKind: actionKind,
            intentRoute: intentRoute,
            intentOutcome: intentOutcome,
            dueAt: dueAt,
            intervalDays: intervalDays,
            repetitions: repetitions,
            easeFactor: easeFactor)
    }

    public var captureItem: CaptureItem {
        CaptureItem(
            id: id,
            createdAt: createdAt,
            sourceText: sourceText,
            language: language,
            idiomatic: idiomatic,
            reasons: reasons,
            actionKind: actionKind,
            intentRoute: intentRoute,
            intentOutcome: intentOutcome)
    }
}
