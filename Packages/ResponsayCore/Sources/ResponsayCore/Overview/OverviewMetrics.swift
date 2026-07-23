import Foundation

/// Health of one capability lane, for the Overview status row.
public enum ProviderStatus: String, Sendable, Equatable, Codable {
    case ready
    case notConfigured
    case error
    case unknown

    /// Map (configured?, healthy?) → status. `nil` health = configured but
    /// not yet probed.
    public static func from(isConfigured: Bool, isHealthy: Bool?) -> ProviderStatus {
        guard isConfigured else { return .notConfigured }
        switch isHealthy {
        case .some(true): return .ready
        case .some(false): return .error
        case .none: return .unknown
        }
    }
}

/// ASR / LLM / TTS status triple shown on the dashboard.
public struct ProviderStatusSummary: Sendable, Equatable, Codable {
    public var asr: ProviderStatus
    public var llm: ProviderStatus
    public var tts: ProviderStatus

    public init(asr: ProviderStatus = .unknown, llm: ProviderStatus = .unknown, tts: ProviderStatus = .unknown) {
        self.asr = asr
        self.llm = llm
        self.tts = tts
    }

    public static let unknown = ProviderStatusSummary()
}

/// One day's rollup for the 7-day bar.
public struct OverviewDayBucket: Sendable, Equatable, Identifiable {
    public let date: Date          // start of that day
    public let segmentCount: Int
    public let characterCount: Int

    public var id: Date { date }

    public init(date: Date, segmentCount: Int, characterCount: Int) {
        self.date = date
        self.segmentCount = segmentCount
        self.characterCount = characterCount
    }
}

/// Aggregated metrics for the main-window Overview (issue 151), derived from the
/// `CaptureStore`. Pure value type; built by `OverviewMetricsBuilder`.
public struct OverviewMetrics: Sendable, Equatable {
    /// Today's character total (字数 — character-based because CJK has no word spaces).
    public let todayCharacterCount: Int
    public let todaySegmentCount: Int
    public let totalSegmentCount: Int
    /// Typing time saved, estimated from total characters (we don't persist audio
    /// length on `CaptureItem`; true recording duration would need a schema field).
    public let estimatedTypingSecondsSaved: Double
    /// Oldest → newest, exactly 7 entries ending today.
    public let last7Days: [OverviewDayBucket]
    public let providerStatus: ProviderStatusSummary

    public init(
        todayCharacterCount: Int,
        todaySegmentCount: Int,
        totalSegmentCount: Int,
        estimatedTypingSecondsSaved: Double,
        last7Days: [OverviewDayBucket],
        providerStatus: ProviderStatusSummary
    ) {
        self.todayCharacterCount = todayCharacterCount
        self.todaySegmentCount = todaySegmentCount
        self.totalSegmentCount = totalSegmentCount
        self.estimatedTypingSecondsSaved = estimatedTypingSecondsSaved
        self.last7Days = last7Days
        self.providerStatus = providerStatus
    }

    public static let empty = OverviewMetrics(
        todayCharacterCount: 0, todaySegmentCount: 0, totalSegmentCount: 0,
        estimatedTypingSecondsSaved: 0, last7Days: [], providerStatus: .unknown
    )
}
