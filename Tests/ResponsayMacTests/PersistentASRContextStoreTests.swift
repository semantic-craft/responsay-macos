import ResponsayCore
import XCTest
@testable import ResponsayMac

@MainActor
final class PersistentASRContextStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var now: Date!
    private var fileURL: URL!
    private let suite = "test.persistentASRContext"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
        now = Date(timeIntervalSince1970: 2_000_000_000)
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("qwen-asr-context-v1.json")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        defaults = nil
        now = nil
        fileURL = nil
        super.tearDown()
    }

    func testDefaultOffKeepsCurrentSessionMemoryButDoesNotRecoverAfterRestart() {
        let firstSession = makeSessionStore()

        firstSession.record("raw current-session text", scope: "com.apple.TextEdit")

        XCTAssertFalse(PersistentASRContextSettings.isEnabled(defaults: defaults))
        XCTAssertEqual(
            firstSession.context(for: "com.apple.TextEdit"),
            ["raw current-session text"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(makeSessionStore().context(for: "com.apple.TextEdit").isEmpty)
    }

    func testOptInRecoversAcrossRestartAndIsolatesByBundleID() {
        PersistentASRContextSettings.setEnabled(true, defaults: defaults, fileURL: fileURL)
        let firstSession = makeSessionStore()
        firstSession.record("Notes raw final", scope: "com.apple.Notes")
        firstSession.record("Mail raw final", scope: "com.apple.mail")
        firstSession.record("must fail closed", scope: nil)

        let restarted = makeSessionStore()

        XCTAssertEqual(restarted.context(for: "com.apple.Notes"), ["Notes raw final"])
        XCTAssertEqual(restarted.context(for: "com.apple.mail"), ["Mail raw final"])
        XCTAssertTrue(restarted.context(for: "com.apple.TextEdit").isEmpty)
        XCTAssertTrue(restarted.context(for: nil).isEmpty)
        XCTAssertTrue(restarted.context(for: "   ").isEmpty)
    }

    func testPerAppCapKeepsOnlyFiveNewestFinalItems() {
        PersistentASRContextSettings.setEnabled(true, defaults: defaults, fileURL: fileURL)
        let session = makeSessionStore()
        for index in 1...6 {
            now = now.addingTimeInterval(1)
            session.record("raw final \(index)", scope: "com.apple.Notes")
        }

        XCTAssertEqual(
            makeSessionStore().context(for: "com.apple.Notes"),
            (2...6).map { "raw final \($0)" })
        XCTAssertEqual(
            PersistentASRContextStore(fileURL: fileURL, now: { self.now })
                .items(for: "com.apple.Notes").count,
            5)
    }

    func testTTLExpiresTheExactTwoHourBoundaryOnRead() throws {
        PersistentASRContextSettings.setEnabled(true, defaults: defaults, fileURL: fileURL)
        let anchor = now!
        let store = PersistentASRContextStore(fileURL: fileURL, now: { self.now })
        now = anchor.addingTimeInterval(-PersistentASRContextStore.timeToLive - 1)
        store.record("older", scope: "com.apple.Notes")
        now = anchor.addingTimeInterval(-PersistentASRContextStore.timeToLive)
        store.record("at boundary in other app", scope: "com.apple.mail")
        now = anchor.addingTimeInterval(-PersistentASRContextStore.timeToLive + 1)
        store.record("inside boundary", scope: "com.apple.Notes")
        now = anchor

        XCTAssertEqual(store.items(for: "com.apple.Notes").map(\.rawFinalText), ["inside boundary"])
        XCTAssertEqual(try rawDiskTexts(), ["inside boundary"])
    }

    func testStartupCleanupPrunesExpiredItems() throws {
        PersistentASRContextSettings.setEnabled(true, defaults: defaults, fileURL: fileURL)
        seedExpiredAndValidItems()

        PersistentASRContextSettings.prepareAtLaunch(defaults: defaults, fileURL: fileURL, now: now)

        XCTAssertEqual(try rawDiskTexts(), ["valid"])
    }

    func testWritePathCleansExpiredItemsBeforeAppending() throws {
        PersistentASRContextSettings.setEnabled(true, defaults: defaults, fileURL: fileURL)
        seedExpiredAndValidItems()
        let store = PersistentASRContextStore(fileURL: fileURL, now: { self.now })

        store.record("new", scope: "com.apple.mail")

        XCTAssertEqual(Set(try rawDiskTexts()), ["valid", "new"])
    }

    func testStartupWithDefaultOffDeletesAPreviouslyPersistedContextFile() {
        XCTAssertTrue(PersistentASRContextSettings.setEnabled(
            true, defaults: defaults, fileURL: fileURL))
        makeSessionStore().record("private raw final", scope: "com.apple.Notes")
        defaults.removeObject(forKey: PersistentASRContextSettings.enabledKey)

        PersistentASRContextSettings.prepareAtLaunch(
            defaults: defaults, fileURL: fileURL, now: now)

        XCTAssertFalse(PersistentASRContextSettings.isEnabled(defaults: defaults))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testPersistsOnlyRawFinalTextAndAppliesAliasesOnlyToOutgoingContext() {
        PersistentASRContextSettings.setEnabled(true, defaults: defaults, fileURL: fileURL)
        XCTAssertEqual(
            CaptureCorrectionLearner.learn(
                wrong: "matis", correct: "Metis", defaults: defaults, notify: { _ in }),
            .learned)
        let session = makeSessionStore()

        session.record("matis is the host", scope: "com.apple.Terminal")

        let diskItems = PersistentASRContextStore(fileURL: fileURL, now: { self.now })
            .items(for: "com.apple.Terminal")
        XCTAssertEqual(diskItems.map(\.rawFinalText), ["matis is the host"])
        XCTAssertEqual(session.context(for: "com.apple.Terminal"), ["Metis is the host"])
    }

    func testRecoveredContextFeedsOfficialQwenPayloadWithoutChangingPrecompiledVocabularyLane() throws {
        defaults.set("qwen-asr-flash", forKey: "byok.asr.provider")
        XCTAssertTrue(ContextHotwordSettings.addManual("Westlaw", defaults: defaults))
        let binding = QwenPrecompiledVocabularySettings.save(
            identifier: "vocab-context-a1b2c3",
            model: QwenRunTaskEndpoint.defaultModel,
            endpoint: QwenRunTaskEndpoint(region: .china),
            vocabularyTerms: ContextHotwordSettings.qwenPersistentHotwords(defaults: defaults),
            defaults: defaults)
        XCTAssertNotNil(binding)
        XCTAssertTrue(PersistentASRContextSettings.setEnabled(
            true, defaults: defaults, fileURL: fileURL))
        makeSessionStore().record("raw recovered final", scope: "com.apple.Notes")
        let recovered = makeSessionStore().context(for: "com.apple.Notes")

        let config = ASRTranscriptionClientFactory.qwenRunTaskConfig(
            defaults: defaults,
            context: recovered,
            contextScope: "com.apple.Notes",
            keyReader: { _ in "synthetic-test-key" })
        let payload = QwenRunTaskASRProtocol.runTask(
            taskID: "task-context-test",
            model: config.model,
            hotwords: config.hotwords,
            precompiledVocabularyID: config.precompiledVocabularyID,
            context: config.context)
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: payload) as? [String: Any])
        let wirePayload = try XCTUnwrap(root["payload"] as? [String: Any])
        let input = try XCTUnwrap(wirePayload["input"] as? [String: Any])
        let messages = try XCTUnwrap(input["context"] as? [[String: Any]])
        let firstContent = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
        let parameters = try XCTUnwrap(wirePayload["parameters"] as? [String: Any])

        XCTAssertEqual(config.contextScope, "com.apple.Notes")
        XCTAssertEqual(config.context, ["raw recovered final"])
        XCTAssertEqual(messages.first?["role"] as? String, "user")
        XCTAssertEqual(firstContent.first?["type"] as? String, "input_text")
        XCTAssertEqual(firstContent.first?["text"] as? String, "raw recovered final")
        XCTAssertEqual(parameters["vocabulary_id"] as? String, "vocab-context-a1b2c3")
        XCTAssertNil(parameters["vocabulary"])
    }

    func testSerializedPayloadContainsOnlyBoundedContextFieldsAndNoRequestConfiguration() throws {
        PersistentASRContextSettings.setEnabled(true, defaults: defaults, fileURL: fileURL)
        makeSessionStore().record("raw final", scope: "com.apple.Notes")

        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any])
        XCTAssertEqual(Set(root.keys), ["schemaVersion", "items"])
        let item = try XCTUnwrap((root["items"] as? [[String: Any]])?.first)
        XCTAssertEqual(
            Set(item.keys),
            ["id", "bundleIdentifier", "rawFinalText", "capturedAt"])
        XCTAssertEqual(item["rawFinalText"] as? String, "raw final")
        XCTAssertNil(item["apiKey"])
        XCTAssertNil(item["audio"])
        XCTAssertNil(item["partial"])
        XCTAssertNil(item["polishedText"])
        XCTAssertNil(item["assistant"])

        let fileAttributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let filePermissions = try XCTUnwrap(fileAttributes[.posixPermissions] as? NSNumber)
        XCTAssertEqual(filePermissions.intValue & 0o777, 0o600)
        let directoryAttributes = try FileManager.default.attributesOfItem(
            atPath: fileURL.deletingLastPathComponent().path)
        let directoryPermissions = try XCTUnwrap(directoryAttributes[.posixPermissions] as? NSNumber)
        XCTAssertEqual(directoryPermissions.intValue & 0o777, 0o700)
    }

    func testOversizedRawFinalIsTruncatedAndInvalidStoragePathFailsClosed() throws {
        XCTAssertTrue(PersistentASRContextSettings.setEnabled(
            true, defaults: defaults, fileURL: fileURL))
        let oversized = String(repeating: "a", count: 401)

        makeSessionStore().record(oversized, scope: "com.apple.Notes")

        XCTAssertEqual(try XCTUnwrap(rawDiskTexts().first).count, 400)

        let blockingFile = fileURL.deletingLastPathComponent().appendingPathComponent("not-a-directory")
        try Data("block".utf8).write(to: blockingFile)
        let invalidURL = blockingFile.appendingPathComponent("context.json")
        let invalidStore = PersistentASRContextStore(fileURL: invalidURL, now: { self.now })
        XCTAssertNil(invalidStore.record("must stay ephemeral", scope: "com.apple.Notes"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: invalidURL.path))
        XCTAssertFalse(PersistentASRContextSettings.setEnabled(
            true, defaults: defaults, fileURL: invalidURL))
        XCTAssertFalse(PersistentASRContextSettings.isEnabled(defaults: defaults))
    }

    func testDisableStaysOffWhenResidualFileCannotBeDeleted() throws {
        let protectedDirectory = fileURL.deletingLastPathComponent()
            .appendingPathComponent("protected", isDirectory: true)
        let protectedFile = protectedDirectory.appendingPathComponent("context.json")
        try FileManager.default.createDirectory(
            at: protectedDirectory, withIntermediateDirectories: true)
        try Data("residual private context".utf8).write(to: protectedFile)
        defaults.set(true, forKey: PersistentASRContextSettings.enabledKey)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500], ofItemAtPath: protectedDirectory.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: protectedDirectory.path)
        }

        XCTAssertFalse(PersistentASRContextSettings.setEnabled(
            false, defaults: defaults, fileURL: protectedFile))

        XCTAssertFalse(PersistentASRContextSettings.isEnabled(defaults: defaults))
        XCTAssertTrue(FileManager.default.fileExists(atPath: protectedFile.path))
    }

    func testDisableAndClearDeleteOnlyContextStoreNotDictionaryAliasesOrTombstones() {
        defaults.set("qwen-asr-flash", forKey: "byok.asr.provider")
        XCTAssertTrue(ContextHotwordSettings.addManual("ManualTerm", defaults: defaults))
        XCTAssertEqual(
            CaptureCorrectionLearner.learn(
                wrong: "matis", correct: "Metis", defaults: defaults, notify: { _ in }),
            .learned)
        _ = AutoLearnHotwordHistorySettings.markUndone(term: "RetiredTerm", defaults: defaults)
        let expectedManual = ContextHotwordSettings.hotwords(defaults: defaults)
        let expectedAliases = AutoLearnHotwordHistorySettings.learnedAliases(defaults: defaults)
        let expectedTombstones = AutoLearnHotwordHistorySettings.tombstonedTerms(defaults: defaults)
        let expectedPrecompiledBinding = QwenPrecompiledVocabularySettings.save(
            identifier: "vocab-private-a1b2c3",
            model: QwenRunTaskEndpoint.defaultModel,
            endpoint: QwenRunTaskEndpoint(region: .china),
            vocabularyTerms: ContextHotwordSettings.qwenPersistentHotwords(defaults: defaults),
            defaults: defaults)
        XCTAssertTrue(expectedManual.contains("ManualTerm"))
        XCTAssertEqual(expectedAliases["matis"], "Metis")
        XCTAssertTrue(expectedTombstones.contains("RetiredTerm"))
        XCTAssertNotNil(expectedPrecompiledBinding)
        PersistentASRContextSettings.setEnabled(true, defaults: defaults, fileURL: fileURL)
        let session = makeSessionStore()
        session.record("private raw final", scope: "com.apple.Notes")

        PersistentASRContextSettings.clear(defaults: defaults, fileURL: fileURL)

        XCTAssertTrue(PersistentASRContextSettings.isEnabled(defaults: defaults))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(ContextHotwordSettings.hotwords(defaults: defaults), expectedManual)
        XCTAssertEqual(AutoLearnHotwordHistorySettings.learnedAliases(defaults: defaults), expectedAliases)
        XCTAssertEqual(AutoLearnHotwordHistorySettings.tombstonedTerms(defaults: defaults), expectedTombstones)
        XCTAssertEqual(
            QwenPrecompiledVocabularySettings.binding(defaults: defaults),
            expectedPrecompiledBinding)
        XCTAssertEqual(session.context(for: "com.apple.Notes"), ["private raw final"])
        XCTAssertTrue(makeSessionStore().context(for: "com.apple.Notes").isEmpty)

        session.record("another raw final", scope: "com.apple.Notes")
        PersistentASRContextSettings.setEnabled(false, defaults: defaults, fileURL: fileURL)

        XCTAssertFalse(PersistentASRContextSettings.isEnabled(defaults: defaults))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(ContextHotwordSettings.hotwords(defaults: defaults), expectedManual)
        XCTAssertEqual(AutoLearnHotwordHistorySettings.learnedAliases(defaults: defaults), expectedAliases)
        XCTAssertEqual(AutoLearnHotwordHistorySettings.tombstonedTerms(defaults: defaults), expectedTombstones)
        XCTAssertEqual(
            QwenPrecompiledVocabularySettings.binding(defaults: defaults),
            expectedPrecompiledBinding)
        XCTAssertEqual(
            session.context(for: "com.apple.Notes"),
            ["private raw final", "another raw final"])
    }

    private func makeSessionStore() -> RecentASRContextSessionStore {
        RecentASRContextSessionStore(defaults: defaults, fileURL: fileURL, now: { self.now })
    }

    private func seedExpiredAndValidItems() {
        let anchor = now!
        let store = PersistentASRContextStore(fileURL: fileURL, now: { self.now })
        now = anchor.addingTimeInterval(-PersistentASRContextStore.timeToLive - 1)
        store.record("expired", scope: "com.apple.Notes")
        now = anchor.addingTimeInterval(-PersistentASRContextStore.timeToLive + 1)
        store.record("valid", scope: "com.apple.Notes")
        now = anchor
    }

    private func rawDiskTexts() throws -> [String] {
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any])
        let items = try XCTUnwrap(root["items"] as? [[String: Any]])
        return try items.map { try XCTUnwrap($0["rawFinalText"] as? String) }
    }
}
