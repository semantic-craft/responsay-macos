import Foundation

/// Persists History entries (audio + text metadata) and owns the lifecycle of
/// their audio files. Spec §6.2.2: "SQLite metadata + audio files in app
/// container". Separate from `CaptureStore`/`ReviewStore` (those carry the
/// idiomatic/teaching cards); History carries the raw capture + media refs.
public protocol HistoryMediaStore: Sendable {
    /// Directory the store owns for audio files. Recorders write audio here so
    /// the store can manage the lifecycle and detect orphans.
    var audioDirectory: URL { get }

    func save(_ item: HistoryItem) throws
    func recent(_ limit: Int) throws -> [HistoryItem]
    func item(id: UUID) throws -> HistoryItem?

    /// Remove one entry and its audio file. No-op if the id is unknown.
    func delete(id: UUID) throws
    /// Remove every entry and all audio in `audioDirectory`.
    func deleteAll() throws

    /// Delete audio files in `audioDirectory` that no entry references.
    /// Returns the removed file URLs.
    @discardableResult
    func cleanupOrphans() throws -> [URL]

    /// Delete entries (and their audio) created before `cutoff`. Returns the
    /// number of entries removed. Backs the "默认 30 天后自动清理" retention.
    @discardableResult
    func prune(olderThan cutoff: Date) throws -> Int
}
