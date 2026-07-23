import Foundation
import ResponsayCore

struct DictationLexicalProfileRefreshDiagnostics: Sendable, Equatable {
    let profileHash: String
    let termCount: Int
    let aliasCount: Int
    let refreshDurationMs: Int
    let staleRefreshRejectedCount: Int
    let privacyRejectionCounts: [String: Int]
    let writeErrorCategory: String?

    func withStaleRefreshRejectedCount(_ count: Int) -> DictationLexicalProfileRefreshDiagnostics {
        DictationLexicalProfileRefreshDiagnostics(
            profileHash: profileHash,
            termCount: termCount,
            aliasCount: aliasCount,
            refreshDurationMs: refreshDurationMs,
            staleRefreshRejectedCount: count,
            privacyRejectionCounts: privacyRejectionCounts,
            writeErrorCategory: writeErrorCategory)
    }
}

enum DictationLexicalProfileSettings {
    static let defaultsKey = "dictation.lexicalProfile.snapshot"
    static let jsonFileName = "dictation-lexical-profile.json"
    static let markdownFileName = "dictation-lexical-profile.md"

    static func current(defaults: UserDefaults = .standard) -> DictationLexicalProfile {
        cached(defaults: defaults) ?? build(defaults: defaults)
    }

    static func cached(defaults: UserDefaults = .standard) -> DictationLexicalProfile? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(DictationLexicalProfile.self, from: data)
    }

    static func refresh(
        defaults: UserDefaults = .standard,
        directory: URL = defaultDirectory(),
        now: Date = Date()
    ) -> DictationLexicalProfileRefreshDiagnostics {
        let start = Date()
        let profile = build(defaults: defaults, now: now)
        return persist(profile: profile, defaults: defaults, directory: directory, startedAt: start)
    }

    static func persist(
        profile: DictationLexicalProfile,
        defaults: UserDefaults = .standard,
        directory: URL = defaultDirectory(),
        startedAt start: Date = Date(),
        staleRefreshRejectedCount: Int = 0
    ) -> DictationLexicalProfileRefreshDiagnostics {
        let data = try? JSONEncoder().encode(profile)
        if let data {
            defaults.set(data, forKey: defaultsKey)
        }

        var writeError: String?
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let data {
                try data.write(to: directory.appendingPathComponent(jsonFileName), options: .atomic)
            }
            try profile.markdownMirror.write(
                to: directory.appendingPathComponent(markdownFileName),
                atomically: true,
                encoding: .utf8)
        } catch {
            writeError = String(describing: type(of: error))
        }

        return DictationLexicalProfileRefreshDiagnostics(
            profileHash: profile.profileHash,
            termCount: profile.terms.count,
            aliasCount: profile.aliases.count,
            refreshDurationMs: Int(Date().timeIntervalSince(start) * 1000),
            staleRefreshRejectedCount: staleRefreshRejectedCount,
            privacyRejectionCounts: profile.privacyRejectionCounts,
            writeErrorCategory: writeError)
    }

    static func scheduleRefresh() {
        Task { await DictationLexicalProfileRefreshCenter.shared.schedule() }
    }

    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Responsay/LexicalProfile", isDirectory: true)
    }

    static func build(defaults: UserDefaults = .standard, now: Date = Date()) -> DictationLexicalProfile {
        DictationLexicalProfileBuilder().build(
            store: ContextHotwordSettings.store(defaults: defaults),
            records: AutoLearnHotwordHistorySettings.records(defaults: defaults),
            now: now)
    }
}

actor DictationLexicalProfileRefreshCenter {
    typealias Build = @Sendable () -> DictationLexicalProfile
    typealias Persist = @Sendable (DictationLexicalProfile, Date, Int) -> DictationLexicalProfileRefreshDiagnostics

    static let shared = DictationLexicalProfileRefreshCenter()

    private let persist: Persist
    private var generation = 0
    private var staleRefreshRejectedCount = 0
    private(set) var latestDiagnostics: DictationLexicalProfileRefreshDiagnostics?

    init(persist: @escaping Persist = { profile, startedAt, staleCount in
        DictationLexicalProfileSettings.persist(
            profile: profile,
            startedAt: startedAt,
            staleRefreshRejectedCount: staleCount)
    }) {
        self.persist = persist
    }

    func schedule(build: @escaping Build = { DictationLexicalProfileSettings.build() }) {
        generation += 1
        let token = generation
        let start = Date()
        Task.detached {
            let profile = build()
            await self.finish(profile, token: token, startedAt: start)
        }
    }

    private func finish(
        _ profile: DictationLexicalProfile,
        token: Int,
        startedAt start: Date
    ) {
        guard token == generation else {
            staleRefreshRejectedCount += 1
            latestDiagnostics = latestDiagnostics?.withStaleRefreshRejectedCount(staleRefreshRejectedCount)
            return
        }
        latestDiagnostics = persist(profile, start, staleRefreshRejectedCount)
    }
}
