import Foundation
import OSLog
import ResponsayCore

enum HistoryRetentionPeriod: Equatable {
    case never
    case days(Int)

    init(storedValue: String?) {
        switch storedValue {
        case "never": self = .never
        case "7": self = .days(7)
        case "90": self = .days(90)
        case "30", nil: self = .days(30)
        default: self = .days(30)
        }
    }

    func cutoff(relativeTo now: Date) -> Date? {
        switch self {
        case .never:
            return nil
        case let .days(days):
            return now.addingTimeInterval(-Double(days) * 24 * 60 * 60)
        }
    }

    var historySummary: String {
        switch self {
        case .never:
            return String(localized: "本机保存 · 不自动清理")
        case .days(7):
            return String(localized: "本机保存 · 7 天后自动清理")
        case .days(90):
            return String(localized: "本机保存 · 90 天后自动清理")
        case .days:
            return String(localized: "本机保存 · 30 天后自动清理")
        }
    }
}

enum HistoryRetentionSettings {
    static let cleanupKey = "historyCleanup"

    static func period(defaults: UserDefaults = .standard) -> HistoryRetentionPeriod {
        HistoryRetentionPeriod(storedValue: defaults.string(forKey: cleanupKey))
    }
}

enum HistoryRetentionCleanup {
    @discardableResult
    static func pruneCaptureRecords(
        in store: CaptureStore,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) throws -> Int {
        guard let cutoff = HistoryRetentionSettings.period(defaults: defaults).cutoff(relativeTo: now) else {
            return 0
        }
        return try store.prune(createdAtOrBefore: cutoff)
    }

    @discardableResult
    static func pruneLearningRecords(
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) -> Int {
        let before = AutoLearnHotwordHistorySettings.rawRecords(defaults: defaults).count
        let after = AutoLearnHotwordHistorySettings.records(defaults: defaults, now: now).count
        return before - after
    }
}

/// One construction path for the live capture history store. Cleanup happens before the store is
/// returned, so app startup and every production read path enforce the currently selected period.
enum CaptureHistoryStoreFactory {
    private static let log = Logger(subsystem: AppBrand.loggerSubsystem, category: "history-retention")

    static func make(
        defaults: UserDefaults = .standard,
        now: Date = Date(),
        pruneExpired: Bool = true
    ) -> CaptureStore {
        let store: CaptureStore
        if let sqlite = try? SQLiteReviewStore.defaultStore() {
            store = ReviewCaptureStore(reviewStore: sqlite)
        } else {
            store = FileCaptureStore.defaultStore()
        }

        if pruneExpired {
            do {
                try HistoryRetentionCleanup.pruneCaptureRecords(
                    in: store,
                    defaults: defaults,
                    now: now)
            } catch {
                log.error("Capture history retention cleanup failed")
            }
        }
        return store
    }
}
