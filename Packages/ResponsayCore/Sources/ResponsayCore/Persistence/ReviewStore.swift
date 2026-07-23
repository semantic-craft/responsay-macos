import Foundation

public protocol ReviewStore: Sendable {
    func save(_ card: ReviewCard) throws
    func update(_ card: ReviewCard) throws
    func recent(_ limit: Int) throws -> [ReviewCard]
    func due(now: Date, limit: Int) throws -> [ReviewCard]
    func count() throws -> Int
    func schemaVersion() throws -> Int
    /// Remove one card by id (History 删除). Default no-op for test doubles.
    func delete(id: UUID) throws
    /// Remove every card (History 清空). Default no-op.
    func deleteAll() throws
}

public extension ReviewStore {
    func delete(id: UUID) throws {}
    func deleteAll() throws {}
}

public extension ReviewStore {
    @discardableResult
    func grade(
        _ card: ReviewCard,
        grade: ReviewGrade,
        reviewedAt: Date = Date()
    ) throws -> ReviewCard {
        let scheduled = SM2Scheduler.schedule(card, grade: grade, reviewedAt: reviewedAt)
        try update(scheduled)
        return scheduled
    }
}
