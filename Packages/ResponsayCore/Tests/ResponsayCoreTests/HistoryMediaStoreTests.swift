import Foundation
import Testing
@testable import ResponsayCore

// 153 — HistoryMediaStore: persists capture history (audio + text metadata),
// deletes single items, and cleans up orphan audio files. Source: spec §6.2.2.

private func tempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func makeStore() throws -> SQLiteHistoryMediaStore {
    let dir = try tempDirectory()
    return try SQLiteHistoryMediaStore(
        databaseURL: dir.appendingPathComponent("history.sqlite"),
        audioDirectory: dir.appendingPathComponent("audio", isDirectory: true))
}

@discardableResult
private func writeAudio(_ name: String, in store: SQLiteHistoryMediaStore) throws -> URL {
    let url = store.audioDirectory.appendingPathComponent(name)
    try Data("fake-wav".utf8).write(to: url)
    return url
}

private func item(
    _ id: String,
    at seconds: TimeInterval,
    audio: URL? = nil,
    action: TextActionKind = .polish,
    privacy: RoutePrivacyMode = .onDevice
) -> HistoryItem {
    HistoryItem(
        id: UUID(uuidString: id)!,
        createdAt: Date(timeIntervalSince1970: seconds),
        sourceAppName: "TextEdit",
        sourceBundleID: "com.apple.TextEdit",
        actionKind: action,
        transcript: "嗯这个方案大概可以",
        resultText: "这个方案大概可以。",
        audioFileURL: audio,
        duration: 3.2,
        providerSummary: "qwen-plus",
        privacyMode: privacy)
}

// MARK: - Schema

@Test func historyItem_codableRoundTrip() throws {
    let original = item(
        "11111111-1111-1111-1111-111111111111", at: 100,
        audio: URL(fileURLWithPath: "/tmp/a.wav"),
        action: .translate, privacy: .cloud)
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(HistoryItem.self, from: data)
    #expect(decoded == original)
}

@Test func historyItem_allowsMinimalNilFields() throws {
    let minimal = HistoryItem(
        id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        createdAt: Date(timeIntervalSince1970: 1),
        actionKind: .dictation,
        privacyMode: .unknown)
    let decoded = try JSONDecoder().decode(
        HistoryItem.self, from: try JSONEncoder().encode(minimal))
    #expect(decoded == minimal)
    #expect(decoded.transcript == nil)
    #expect(decoded.audioFileURL == nil)
    #expect(decoded.duration == nil)
}

@Test func historyItem_optionalSourcePresentationSearchAndExportNeverInventRaw() {
    let finalOnly = HistoryItem(
        actionKind: .polish,
        transcript: nil,
        resultText: "Approved final text.",
        privacyMode: .unknown)
    let retainedSourceOnly = HistoryItem(
        actionKind: .dictation,
        transcript: "Actual retained source",
        resultText: nil,
        privacyMode: .unknown)
    let textless = HistoryItem(
        actionKind: .other,
        transcript: nil,
        resultText: nil,
        privacyMode: .unknown)

    #expect(finalOnly.displayText == "Approved final text.")
    #expect(finalOnly.sourceDisplayText == "原口述未保存")
    #expect(finalOnly.matchesSearch("approved"))
    #expect(!finalOnly.matchesSearch("原口述未保存"))
    #expect(!finalOnly.matchesSearch("actual retained"))
    #expect(finalOnly.exportText == "Approved final text.")

    #expect(retainedSourceOnly.sourceDisplayText == "Actual retained source")
    #expect(retainedSourceOnly.matchesSearch("retained"))
    #expect(retainedSourceOnly.exportText == "Actual retained source")

    #expect(textless.displayText.isEmpty)
    #expect(textless.sourceDisplayText == "原口述未保存")
    #expect(textless.exportText == "原口述未保存")
}

// MARK: - Save / fetch lifecycle

@Test func historyStore_saveAndRecentRoundTrip() throws {
    let store = try makeStore()
    let audio = try writeAudio("33333333.wav", in: store)
    let saved = item("33333333-3333-3333-3333-333333333333", at: 50, audio: audio,
                     action: .translate, privacy: .cloud)

    try store.save(saved)
    let fetched = try #require(try store.recent(10).first)

    #expect(fetched.id == saved.id)
    #expect(fetched.createdAt == saved.createdAt)
    #expect(fetched.sourceAppName == "TextEdit")
    #expect(fetched.sourceBundleID == "com.apple.TextEdit")
    #expect(fetched.actionKind == .translate)
    #expect(fetched.transcript == saved.transcript)
    #expect(fetched.resultText == saved.resultText)
    #expect(fetched.duration == 3.2)
    #expect(fetched.providerSummary == "qwen-plus")
    #expect(fetched.privacyMode == .cloud)
    // Audio URL is resolved back under the store's managed directory.
    #expect(fetched.audioFileURL?.lastPathComponent == "33333333.wav")
    #expect(fetched.audioFileURL?.deletingLastPathComponent().path
            == store.audioDirectory.path)
    #expect(FileManager.default.fileExists(atPath: fetched.audioFileURL!.path))
}

@Test func historyStore_recentOrdersNewestFirstAndRespectsLimit() throws {
    let store = try makeStore()
    try store.save(item("aaaaaaaa-0000-0000-0000-000000000001", at: 10))
    try store.save(item("aaaaaaaa-0000-0000-0000-000000000002", at: 30))
    try store.save(item("aaaaaaaa-0000-0000-0000-000000000003", at: 20))

    let recent = try store.recent(2)
    #expect(recent.map { $0.createdAt.timeIntervalSince1970 } == [30, 20])
}

@Test func historyStore_itemByIdReturnsNilWhenMissing() throws {
    let store = try makeStore()
    let saved = item("bbbbbbbb-0000-0000-0000-000000000001", at: 5)
    try store.save(saved)

    #expect(try store.item(id: saved.id)?.id == saved.id)
    #expect(try store.item(id: UUID()) == nil)
}

@Test func historyStore_persistsAcrossReopen() throws {
    let dir = try tempDirectory()
    let dbURL = dir.appendingPathComponent("history.sqlite")
    let audioDir = dir.appendingPathComponent("audio", isDirectory: true)
    let first = try SQLiteHistoryMediaStore(databaseURL: dbURL, audioDirectory: audioDir)
    try first.save(item("cccccccc-0000-0000-0000-000000000001", at: 7))

    let reopened = try SQLiteHistoryMediaStore(databaseURL: dbURL, audioDirectory: audioDir)
    #expect(try reopened.recent(10).count == 1)
}

// MARK: - Delete single + delete all

@Test func historyStore_deleteRemovesRowAndAudioFileButKeepsOthers() throws {
    let store = try makeStore()
    let keepAudio = try writeAudio("keep.wav", in: store)
    let dropAudio = try writeAudio("drop.wav", in: store)
    let keep = item("dddddddd-0000-0000-0000-000000000001", at: 10, audio: keepAudio)
    let drop = item("dddddddd-0000-0000-0000-000000000002", at: 20, audio: dropAudio)
    try store.save(keep)
    try store.save(drop)

    try store.delete(id: drop.id)

    #expect(try store.recent(10).map(\.id) == [keep.id])
    #expect(!FileManager.default.fileExists(atPath: dropAudio.path))
    #expect(FileManager.default.fileExists(atPath: keepAudio.path))
}

@Test func historyStore_deleteMissingIdIsNoOp() throws {
    let store = try makeStore()
    try store.save(item("eeeeeeee-0000-0000-0000-000000000001", at: 1))
    try store.delete(id: UUID())   // must not throw
    #expect(try store.recent(10).count == 1)
}

@Test func historyStore_deleteAllWipesRowsAndManagedAudio() throws {
    let store = try makeStore()
    let a = try writeAudio("a.wav", in: store)
    let b = try writeAudio("b.wav", in: store)
    try store.save(item("ffffffff-0000-0000-0000-000000000001", at: 10, audio: a))
    try store.save(item("ffffffff-0000-0000-0000-000000000002", at: 20, audio: b))

    try store.deleteAll()

    #expect(try store.recent(10).isEmpty)
    #expect(!FileManager.default.fileExists(atPath: a.path))
    #expect(!FileManager.default.fileExists(atPath: b.path))
}

// MARK: - Orphan cleanup + retention

@Test func historyStore_cleanupOrphansRemovesUnreferencedAudioOnly() throws {
    let store = try makeStore()
    let referenced = try writeAudio("ref.wav", in: store)
    _ = try writeAudio("orphan1.wav", in: store)
    _ = try writeAudio("orphan2.wav", in: store)
    try store.save(item("12121212-0000-0000-0000-000000000001", at: 10, audio: referenced))

    let removed = try store.cleanupOrphans()

    #expect(Set(removed.map(\.lastPathComponent)) == ["orphan1.wav", "orphan2.wav"])
    #expect(FileManager.default.fileExists(atPath: referenced.path))
    let left = try FileManager.default.contentsOfDirectory(atPath: store.audioDirectory.path)
    #expect(left == ["ref.wav"])
}

@Test func historyStore_cleanupOrphansNoopWhenAllReferenced() throws {
    let store = try makeStore()
    let a = try writeAudio("only.wav", in: store)
    try store.save(item("13131313-0000-0000-0000-000000000001", at: 10, audio: a))

    #expect(try store.cleanupOrphans().isEmpty)
    #expect(FileManager.default.fileExists(atPath: a.path))
}

@Test func historyStore_pruneOlderThanRemovesOldItemsAndTheirAudio() throws {
    let store = try makeStore()
    let oldAudio = try writeAudio("old.wav", in: store)
    let newAudio = try writeAudio("new.wav", in: store)
    let old = item("14141414-0000-0000-0000-000000000001", at: 100, audio: oldAudio)
    let fresh = item("14141414-0000-0000-0000-000000000002", at: 500, audio: newAudio)
    try store.save(old)
    try store.save(fresh)

    let removedCount = try store.prune(olderThan: Date(timeIntervalSince1970: 300))

    #expect(removedCount == 1)
    #expect(try store.recent(10).map(\.id) == [fresh.id])
    #expect(!FileManager.default.fileExists(atPath: oldAudio.path))
    #expect(FileManager.default.fileExists(atPath: newAudio.path))
}
