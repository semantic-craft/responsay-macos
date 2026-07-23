import Foundation

/// Builds `OverviewMetrics` from raw capture items. `now`, `calendar`, and the
/// provider status are injected so the rollup is deterministic + testable
/// (issue 151). The provider status comes from the health layer, not the store.
public struct OverviewMetricsBuilder: Sendable {
    /// Rough typing speed used to estimate "省下打字" (characters per second).
    public static let defaultTypingCharsPerSecond = 3.5

    public init() {}

    public func build(
        from items: [CaptureItem],
        now: Date,
        calendar: Calendar = .current,
        status: ProviderStatusSummary = .unknown,
        typingCharsPerSecond: Double = OverviewMetricsBuilder.defaultTypingCharsPerSecond
    ) -> OverviewMetrics {
        let todayItems = items.filter { calendar.isDate($0.createdAt, inSameDayAs: now) }
        let todayCharacters = todayItems.reduce(0) { $0 + Self.characterCount($1) }
        let totalCharacters = items.reduce(0) { $0 + Self.characterCount($1) }

        let rate = typingCharsPerSecond > 0 ? typingCharsPerSecond : Self.defaultTypingCharsPerSecond
        let secondsSaved = Double(totalCharacters) / rate

        return OverviewMetrics(
            todayCharacterCount: todayCharacters,
            todaySegmentCount: todayItems.count,
            totalSegmentCount: items.count,
            estimatedTypingSecondsSaved: secondsSaved,
            last7Days: Self.last7Days(items: items, now: now, calendar: calendar),
            providerStatus: status
        )
    }

    // MARK: - Helpers

    /// The character total for one item — the approved result if present, else the
    /// retained source. A record with neither contributes zero.
    static func characterCount(_ item: CaptureItem) -> Int {
        item.idiomatic.isEmpty ? (item.sourceText?.count ?? 0) : item.idiomatic.count
    }

    /// Exactly 7 day buckets, oldest → newest, ending on `now`'s day.
    static func last7Days(items: [CaptureItem], now: Date, calendar: Calendar) -> [OverviewDayBucket] {
        let startOfToday = calendar.startOfDay(for: now)
        return (0..<7).reversed().map { offset -> OverviewDayBucket in
            let day = calendar.date(byAdding: .day, value: -offset, to: startOfToday) ?? startOfToday
            let dayItems = items.filter { calendar.isDate($0.createdAt, inSameDayAs: day) }
            return OverviewDayBucket(
                date: day,
                segmentCount: dayItems.count,
                characterCount: dayItems.reduce(0) { $0 + characterCount($1) }
            )
        }
    }
}
