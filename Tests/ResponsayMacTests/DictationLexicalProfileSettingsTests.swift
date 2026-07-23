import XCTest
import ResponsayCore
@testable import ResponsayMac

final class DictationLexicalProfileSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var directory: URL!
    private let suite = "test.dictationLexicalProfile"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
        defaults = nil
        directory = nil
        super.tearDown()
    }

    func testRefreshWritesJSONMarkdownAndCachedSnapshot() throws {
        ContextHotwordSettings.addManual("Claude Code", defaults: defaults)
        AutoLearnHotwordHistorySettings.append(
            HotwordCandidateProposal(
                term: "Claude Code",
                source: .localRules,
                confidence: 0.92,
                reason: "用户纠正",
                sourceTerm: "Cloud Code",
                appName: "Notes",
                windowTitle: "论文草稿"),
            status: .added,
            defaults: defaults)

        let diagnostics = DictationLexicalProfileSettings.refresh(defaults: defaults, directory: directory)
        let cached = try XCTUnwrap(DictationLexicalProfileSettings.cached(defaults: defaults))
        let markdown = try String(contentsOf: directory.appendingPathComponent(DictationLexicalProfileSettings.markdownFileName))

        XCTAssertEqual(cached.profileHash, diagnostics.profileHash)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(DictationLexicalProfileSettings.jsonFileName).path))
        XCTAssertTrue(markdown.contains("Cloud Code -> Claude Code"))
        XCTAssertFalse(markdown.contains("论文草稿"))
    }

    func testCachedProfileFeedsBiasingRoutes() throws {
        ContextHotwordSettings.addManual("Claude Code", defaults: defaults)
        AutoLearnHotwordHistorySettings.append(
            HotwordCandidateProposal(
                term: "Claude Code",
                source: .localRules,
                confidence: 0.92,
                reason: "用户纠正",
                sourceTerm: "Cloud Code",
                appName: "Notes",
                windowTitle: nil),
            status: .added,
            defaults: defaults)
        let profile = DictationLexicalProfileSettings.build(defaults: defaults)
        defaults.set(try JSONEncoder().encode(profile), forKey: DictationLexicalProfileSettings.defaultsKey)
        defaults.removeObject(forKey: ContextHotwordSettings.defaultsKey)
        defaults.removeObject(forKey: ContextHotwordSettings.autoDefaultsKey)
        defaults.removeObject(forKey: ContextHotwordSettings.autoMetadataDefaultsKey)
        defaults.removeObject(forKey: AutoLearnHotwordHistorySettings.historyKey)

        let sets = ContextHotwordSettings.biasingSets(defaults: defaults)

        XCTAssertTrue(sets.weakPrompt.contains("Claude Code"))
        XCTAssertEqual(sets.learnedAliases["Cloud Code"], "Claude Code")
        XCTAssertEqual(sets.enforce("Cloud Code").text, "Claude Code")
    }

    func testProtectedAppRecordIsExcludedFromProfile() {
        AutoLearnHotwordHistorySettings.append(
            HotwordCandidateProposal(
                term: "Claude Code",
                source: .localRules,
                confidence: 0.92,
                reason: "用户纠正",
                sourceTerm: "Cloud Code",
                appName: "Xcode",
                windowTitle: "main.swift"),
            status: .added,
            defaults: defaults)

        let profile = DictationLexicalProfileSettings.build(defaults: defaults)

        XCTAssertTrue(profile.aliases.isEmpty)
        XCTAssertEqual(profile.privacyRejectionCounts["protectedApp"], 1)
    }

    func testRefreshRecordsWriteFailureWithoutDroppingCachedSnapshot() throws {
        ContextHotwordSettings.addManual("Claude Code", defaults: defaults)
        try "not a directory".write(to: directory, atomically: true, encoding: .utf8)

        let diagnostics = DictationLexicalProfileSettings.refresh(defaults: defaults, directory: directory)
        let cached = try XCTUnwrap(DictationLexicalProfileSettings.cached(defaults: defaults))

        XCTAssertEqual(cached.profileHash, diagnostics.profileHash)
        XCTAssertNotNil(diagnostics.writeErrorCategory)
    }

    func testStaleRefreshDoesNotOverwriteLatestSnapshot() async throws {
        let oldProfile = makeProfile(term: "Old Term")
        let newProfile = makeProfile(term: "New Term")
        let spy = LexicalProfilePersistSpy()
        let center = DictationLexicalProfileRefreshCenter(persist: spy.persist)

        await center.schedule {
            Thread.sleep(forTimeInterval: 0.05)
            return oldProfile
        }
        await center.schedule {
            newProfile
        }
        try await Task.sleep(nanoseconds: 200_000_000)

        let latestDiagnostics = await center.latestDiagnostics
        let diagnostics = try XCTUnwrap(latestDiagnostics)

        XCTAssertEqual(diagnostics.profileHash, newProfile.profileHash)
        XCTAssertEqual(diagnostics.staleRefreshRejectedCount, 1)
        XCTAssertEqual(spy.persistedHashes, [newProfile.profileHash])
    }

    private func makeProfile(term: String) -> DictationLexicalProfile {
        DictationLexicalProfileBuilder().build(
            store: HotwordStore(userTerms: [term], seeds: [:]),
            records: [],
            now: Date(timeIntervalSince1970: 1))
    }
}

private final class LexicalProfilePersistSpy: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var persistedHashes: [String] = []

    func persist(
        _ profile: DictationLexicalProfile,
        _ startedAt: Date,
        _ staleCount: Int
    ) -> DictationLexicalProfileRefreshDiagnostics {
        lock.lock()
        persistedHashes.append(profile.profileHash)
        lock.unlock()
        return DictationLexicalProfileRefreshDiagnostics(
            profileHash: profile.profileHash,
            termCount: profile.terms.count,
            aliasCount: profile.aliases.count,
            refreshDurationMs: Int(Date().timeIntervalSince(startedAt) * 1000),
            staleRefreshRejectedCount: staleCount,
            privacyRejectionCounts: profile.privacyRejectionCounts,
            writeErrorCategory: nil)
    }
}
