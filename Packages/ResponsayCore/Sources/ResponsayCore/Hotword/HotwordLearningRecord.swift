import Foundation

public struct HotwordLearningRecord: Sendable, Codable, Equatable, Identifiable {
    public let id: UUID
    public let term: String
    public let source: HotwordLearningSource
    public var status: HotwordLearningRecordStatus
    public let reason: String
    public var learnedAt: Date
    public let sourceTerm: String?
    public let appName: String?
    public let windowTitle: String?
    /// 454 — the candidate's confidence at learn time (for the audit panel). Optional so older
    /// persisted records (no `confidence` key) keep decoding via synthesized `decodeIfPresent`.
    public let confidence: Double?

    public init(
        id: UUID = UUID(),
        term: String,
        source: HotwordLearningSource,
        status: HotwordLearningRecordStatus,
        reason: String,
        learnedAt: Date,
        sourceTerm: String? = nil,
        appName: String? = nil,
        windowTitle: String? = nil,
        confidence: Double? = nil
    ) {
        self.id = id
        self.term = term
        self.source = source
        self.status = status
        self.reason = reason
        self.learnedAt = learnedAt
        self.sourceTerm = sourceTerm
        self.appName = appName
        self.windowTitle = windowTitle
        self.confidence = confidence
    }
}
