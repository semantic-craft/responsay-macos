import Foundation

public struct ReviewCaptureStore: CaptureStore {
    private let reviewStore: any ReviewStore

    public init(reviewStore: any ReviewStore) {
        self.reviewStore = reviewStore
    }

    public func save(_ item: CaptureItem) throws {
        try reviewStore.save(ReviewCard(capture: item))
        NotificationCenter.default.post(name: .captureStoreDidChange, object: nil)
    }

    public func recent(_ limit: Int) throws -> [CaptureItem] {
        try reviewStore.recent(limit).map(\.captureItem)
    }

    public func overviewMetrics(
        now: Date,
        calendar: Calendar,
        status: ProviderStatusSummary,
        typingCharsPerSecond: Double
    ) throws -> OverviewMetrics {
        try reviewStore.overviewMetrics(
            now: now,
            calendar: calendar,
            status: status,
            typingCharsPerSecond: typingCharsPerSecond)
    }

    public func delete(id: UUID) throws {
        try reviewStore.delete(id: id)
        NotificationCenter.default.post(name: .captureStoreDidChange, object: nil)
    }

    public func deleteAll() throws {
        try reviewStore.deleteAll()
        NotificationCenter.default.post(name: .captureStoreDidChange, object: nil)
    }

    @discardableResult
    public func prune(createdAtOrBefore cutoff: Date) throws -> Int {
        let removedCount = try reviewStore.prune(createdAtOrBefore: cutoff)
        if removedCount > 0 {
            NotificationCenter.default.post(name: .captureStoreDidChange, object: nil)
        }
        return removedCount
    }
}
