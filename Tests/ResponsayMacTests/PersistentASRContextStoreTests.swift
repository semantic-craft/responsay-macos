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
            makePersistentStore().items(for: "com.apple.Notes").count,
            5)
    }

    func testTTLExpiresTheExactTwoHourBoundaryOnRead() throws {
        PersistentASRContextSettings.setEnabled(true, defaults: defaults, fileURL: fileURL)
        let anchor = now!
        let store = makePersistentStore()
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

        PersistentASRContextSettings.prepareAtLaunch(
            defaults: defaults,
            fileURL: fileURL,
            now: { self.now },
            expiryScheduler: { _, _ in {} })

        XCTAssertEqual(try rawDiskTexts(), ["valid"])
    }

    func testWritePathCleansExpiredItemsBeforeAppending() throws {
        PersistentASRContextSettings.setEnabled(true, defaults: defaults, fileURL: fileURL)
        seedExpiredAndValidItems()
        let store = makePersistentStore()

        store.record("new", scope: "com.apple.mail")

        XCTAssertEqual(Set(try rawDiskTexts()), ["valid", "new"])
    }

    func testScheduledCleanupEnforcesTTLWithoutAnotherReadOrWrite() throws {
        PersistentASRContextSettings.setEnabled(true, defaults: defaults, fileURL: fileURL)
        let anchor = now!
        var scheduledDelays: [UUID: TimeInterval] = [:]
        var scheduledActions: [UUID: @MainActor () -> Void] = [:]
        var cancelledTimers = Set<UUID>()
        var latestTimerID: UUID?
        let store = PersistentASRContextStore(
            fileURL: fileURL,
            now: { self.now },
            expiryScheduler: { delay, action in
                let timerID = UUID()
                scheduledDelays[timerID] = delay
                scheduledActions[timerID] = action
                latestTimerID = timerID
                return { cancelledTimers.insert(timerID) }
            })
        store.record("first", scope: "com.apple.Notes")
        let firstTimerID = try XCTUnwrap(latestTimerID)
        now = anchor.addingTimeInterval(60)
        store.record("second", scope: "com.apple.Notes")
        let secondTimerID = try XCTUnwrap(latestTimerID)

        XCTAssertEqual(
            try XCTUnwrap(scheduledDelays[secondTimerID]),
            PersistentASRContextStore.timeToLive - 60,
            accuracy: 0.001)
        XCTAssertTrue(cancelledTimers.contains(firstTimerID))
        XCTAssertEqual(
            Set(scheduledActions.keys).subtracting(cancelledTimers),
            [secondTimerID])

        now = anchor.addingTimeInterval(PersistentASRContextStore.timeToLive)
        scheduledActions[secondTimerID]?()
        let finalTimerID = try XCTUnwrap(latestTimerID)

        XCTAssertEqual(try rawDiskTexts(), ["second"])
        XCTAssertEqual(try XCTUnwrap(scheduledDelays[finalTimerID]), 60, accuracy: 0.001)
        XCTAssertTrue(cancelledTimers.contains(secondTimerID))
        XCTAssertEqual(
            Set(scheduledActions.keys).subtracting(cancelledTimers),
            [finalTimerID])

        now = anchor.addingTimeInterval(PersistentASRContextStore.timeToLive + 60)
        scheduledActions[finalTimerID]?()

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(cancelledTimers.contains(finalTimerID))
        XCTAssertTrue(Set(scheduledActions.keys).subtracting(cancelledTimers).isEmpty)
    }

    func testStartupSchedulerUsesLiveClockAndFailsOffIfExpiryCleanupCannotRemoveFile() throws {
        XCTAssertTrue(PersistentASRContextSettings.setEnabled(
            true, defaults: defaults, fileURL: fileURL))
        let anchor = now!
        let seedStore = PersistentASRContextStore(
            fileURL: fileURL,
            now: { self.now },
            expiryScheduler: { _, _ in {} })
        seedStore.record("startup private raw final", scope: "com.apple.Notes")
        var scheduledAction: (@MainActor () -> Void)?
        PersistentASRContextSettings.prepareAtLaunch(
            defaults: defaults,
            fileURL: fileURL,
            now: { self.now },
            expiryScheduler: { _, action in
                scheduledAction = action
                return {}
            })
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: fileURL.path)
        defer {
            try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: fileURL.path)
        }

        now = anchor.addingTimeInterval(PersistentASRContextStore.timeToLive)
        scheduledAction?()

        XCTAssertFalse(PersistentASRContextSettings.isEnabled(defaults: defaults))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testReadCleanupFailureDisablesPersistence() throws {
        XCTAssertTrue(PersistentASRContextSettings.setEnabled(
            true, defaults: defaults, fileURL: fileURL))
        let session = makeSessionStore()
        session.record("private raw final", scope: "com.apple.Notes")
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: fileURL.path)
        defer {
            try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: fileURL.path)
        }
        now = now.addingTimeInterval(PersistentASRContextStore.timeToLive)

        XCTAssertTrue(session.context(for: "com.apple.Notes").isEmpty)

        XCTAssertFalse(PersistentASRContextSettings.isEnabled(defaults: defaults))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testStartupWithDefaultOffDeletesAPreviouslyPersistedContextFile() {
        XCTAssertTrue(PersistentASRContextSettings.setEnabled(
            true, defaults: defaults, fileURL: fileURL))
        makeSessionStore().record("private raw final", scope: "com.apple.Notes")
        defaults.removeObject(forKey: PersistentASRContextSettings.enabledKey)

        PersistentASRContextSettings.prepareAtLaunch(
            defaults: defaults, fileURL: fileURL, now: { self.now })

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

        let diskItems = makePersistentStore().items(for: "com.apple.Terminal")
        XCTAssertEqual(diskItems.map(\.rawFinalText), ["matis is the host"])
        XCTAssertEqual(session.context(for: "com.apple.Terminal"), ["Metis is the host"])
    }

    func testRecoveredContextFeedsEffectiveQwenConfigWithoutChangingPrecompiledVocabularyLane() {
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
        XCTAssertEqual(config.contextScope, "com.apple.Notes")
        XCTAssertEqual(config.context, ["raw recovered final"])
        XCTAssertEqual(config.precompiledVocabularyID, "vocab-context-a1b2c3")
        XCTAssertTrue(config.hotwords.isEmpty)
        XCTAssertTrue(config.heartbeat)
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
        let invalidStore = makePersistentStore(at: invalidURL)
        XCTAssertNil(invalidStore.record("must stay ephemeral", scope: "com.apple.Notes"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: invalidURL.path))
        XCTAssertFalse(PersistentASRContextSettings.setEnabled(
            true, defaults: defaults, fileURL: invalidURL))
        XCTAssertFalse(PersistentASRContextSettings.isEnabled(defaults: defaults))
    }

    func testRuntimeWriteFailureDisablesPersistenceButKeepsCurrentSessionContext() throws {
        XCTAssertTrue(PersistentASRContextSettings.setEnabled(
            true, defaults: defaults, fileURL: fileURL))
        let session = makeSessionStore()
        let blockingPath = fileURL.deletingLastPathComponent()
        try FileManager.default.removeItem(at: blockingPath)
        try Data("not a directory".utf8).write(to: blockingPath)

        session.record("ephemeral raw final", scope: "com.apple.Notes")

        XCTAssertFalse(PersistentASRContextSettings.isEnabled(defaults: defaults))
        XCTAssertEqual(session.context(for: "com.apple.Notes"), ["ephemeral raw final"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
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
        RecentASRContextSessionStore(
            defaults: defaults,
            fileURL: fileURL,
            now: { self.now },
            expiryScheduler: { _, _ in {} })
    }

    private func makePersistentStore(at targetURL: URL? = nil) -> PersistentASRContextStore {
        PersistentASRContextStore(
            fileURL: targetURL ?? fileURL,
            now: { self.now },
            expiryScheduler: { _, _ in {} })
    }

    private func seedExpiredAndValidItems() {
        let anchor = now!
        let store = makePersistentStore()
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
