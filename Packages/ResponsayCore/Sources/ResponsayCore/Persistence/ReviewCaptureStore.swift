import Foundation

public struct ReviewCaptureStore: CaptureStore {
    private let reviewStore: any ReviewStore

    public init(reviewStore: any ReviewStore) {
        self.reviewStore = reviewStore
    }

    public func save(_ item: CaptureItem) throws {
        try reviewStore.save(ReviewCard(capture: item))
    }

    public func recent(_ limit: Int) throws -> [CaptureItem] {
        try reviewStore.recent(limit).map(\.captureItem)
    }

    public func delete(id: UUID) throws {
        try reviewStore.delete(id: id)
    }

    public func deleteAll() throws {
        try reviewStore.deleteAll()
    }
}
