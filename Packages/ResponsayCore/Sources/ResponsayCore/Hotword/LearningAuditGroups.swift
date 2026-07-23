import Foundation

/// The auto-learn audit panel's brain (454): splits the learning ledger into the four visible
/// buckets, newest-first within each (the ledger is already newest-first), and decorates each row
/// with its sensitivity — derived from the term at display time (a pure function, so there's no
/// need to persist it). Pure data transform — no UI, no I/O → headless-testable.
public struct LearningAuditGroups: Sendable, Equatable {
    /// One ledger record plus its derived sensitivity. Carries the whole record (lossless) so the
    /// panel can act on it (approve needs the original source/reason for dictionary provenance).
    public struct Row: Sendable, Equatable, Identifiable {
        public let record: HotwordLearningRecord
        /// Why this term is interrupt-worthy, derived from the term (nil = ordinary).
        public let sensitivityReason: SpecializedReason?

        public var id: UUID { record.id }
        public var term: String { record.term }
        public var confidence: Double? { record.confidence }
    }

    public let pending: [Row]
    public let added: [Row]
    public let ignored: [Row]
    public let undone: [Row]

    public init(
        records: [HotwordLearningRecord],
        classifier: HotwordSensitivityClassifier = HotwordSensitivityClassifier()
    ) {
        func row(_ record: HotwordLearningRecord) -> Row {
            let reason: SpecializedReason?
            if case let .specialized(hit) = classifier.classify(record.term) { reason = hit } else { reason = nil }
            return Row(record: record, sensitivityReason: reason)
        }
        pending = records.filter { $0.status == .pending }.map(row)
        added = records.filter { $0.status == .added }.map(row)
        ignored = records.filter { $0.status == .ignored }.map(row)
        undone = records.filter { $0.status == .undone }.map(row)
    }
}
