import Foundation

/// 一条"随手记/错题本"记录:可选原口述 + 地道版本 + 为什么。
public struct CaptureItem: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let createdAt: Date
    /// `nil` means the original utterance was intentionally not retained.
    public let sourceText: String?
    public let language: String   // CaptureLocale.rawValue, e.g. "en-US"
    public let idiomatic: String
    public let reasons: [String]
    /// Which text action produced this capture (381). Persisted so History filters
    /// exactly instead of guessing from `language`. Old records (no field) read as `.dictation`.
    public let actionKind: TextActionKind
    /// The visible compile route for an Intent-aware record (`intentPlan` = 校验成稿, `ordinaryPolished`
    /// = 普通整理), or `nil` for every non-intent capture. History surfaces it; only approved finals
    /// carry it (#565 / spec decision 29).
    public let intentRoute: IntentInsertRoute?
    /// The coarse terminal disposition of an approved Intent-aware final (`inserted` / `copied`), or
    /// `nil` for non-intent captures. Content-free — no raw / plan / entity value ever lands here.
    public let intentOutcome: IntentHistoryOutcome?

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        sourceText: String?,
        language: String,
        idiomatic: String,
        reasons: [String],
        actionKind: TextActionKind = .dictation,
        intentRoute: IntentInsertRoute? = nil,
        intentOutcome: IntentHistoryOutcome? = nil
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
    }

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, sourceText, language, idiomatic, reasons, actionKind
        case intentRoute, intentOutcome
    }

    /// Tolerant decode: old `captures.json` source strings remain exact; a missing or
    /// explicit-null source means the original utterance was not retained. Old records
    /// without `actionKind` still read as `.dictation`; records predating the Intent-aware route/
    /// outcome fields decode them as `nil`. `encode(to:)` stays synthesized.
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
    }
}
