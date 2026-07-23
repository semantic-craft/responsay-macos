import Testing
import Foundation
@testable import ResponsayCore

private func tempURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("json")
}

@Test func fileStore_saveThenRecent_roundTrips() throws {
    let url = tempURL()
    let store = FileCaptureStore(fileURL: url)
    let item = CaptureItem(sourceText: "a", language: "en-US", idiomatic: "A.", reasons: [])
    try store.save(item)
    let recent = try store.recent(10)
    #expect(recent.count == 1)
    #expect(recent.first?.idiomatic == "A.")
}

@Test func fileStore_persistsAcrossInstances_newestFirst() throws {
    let url = tempURL()
    try FileCaptureStore(fileURL: url).save(
        CaptureItem(createdAt: Date(timeIntervalSince1970: 1), sourceText: "old",
                    language: "en-US", idiomatic: "Old.", reasons: []))
    try FileCaptureStore(fileURL: url).save(
        CaptureItem(createdAt: Date(timeIntervalSince1970: 2), sourceText: "new",
                    language: "en-US", idiomatic: "New.", reasons: []))
    let recent = try FileCaptureStore(fileURL: url).recent(10)
    #expect(recent.map(\.idiomatic) == ["New.", "Old."])
}

@Test func fileStore_restartPreservesMixedOptionalSources() throws {
    let url = tempURL()
    let store = FileCaptureStore(fileURL: url)
    try store.save(CaptureItem(
        createdAt: Date(timeIntervalSince1970: 1),
        sourceText: "retained verbatim",
        language: "en-US",
        idiomatic: "Retained result.",
        reasons: []))
    try store.save(CaptureItem(
        createdAt: Date(timeIntervalSince1970: 2),
        sourceText: nil,
        language: "zh-CN",
        idiomatic: "仅保存结果",
        reasons: []))

    let reopened = try FileCaptureStore(fileURL: url).recent(10)

    #expect(reopened.map(\.sourceText) == [nil, "retained verbatim"])
    #expect(reopened.map(\.idiomatic) == ["仅保存结果", "Retained result."])
}
