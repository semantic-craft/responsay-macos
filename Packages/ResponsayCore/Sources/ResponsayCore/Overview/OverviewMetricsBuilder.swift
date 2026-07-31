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
        var accumulator = OverviewMetricsAccumulator(
            now: now,
            calendar: calendar,
            status: status,
            typingCharsPerSecond: typingCharsPerSecond)
        items.forEach { accumulator.add($0) }
        return accumulator.metrics()
    }

    // MARK: - Helpers

    /// The character total for one item — the approved result if present, else the
    /// retained source. A record with neither contributes zero.
    static func characterCount(_ item: CaptureItem) -> Int {
        visibleText(finalText: item.idiomatic, sourceText: item.sourceText)?.count ?? 0
    }

    static func visibleText(finalText: String, sourceText: String?) -> String? {
        let final = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !final.isEmpty { return final }
        let source = sourceText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return source.isEmpty ? nil : source
    }
}

/// Fixed-size accumulator used by both array-backed and SQLite-backed stores.
/// It never retains transcript text and keeps exactly seven local-calendar buckets.
struct OverviewMetricsAccumulator {
    private let now: Date
    private let calendar: Calendar
    private let status: ProviderStatusSummary
    private let typingCharsPerSecond: Double
    private let bucketDates: [Date]
    private var bucketSegmentCounts = Array(repeating: 0, count: 7)
    private var bucketCharacterCounts = Array(repeating: 0, count: 7)
    private var todayCharacterCount = 0
    private var todaySegmentCount = 0
    private var totalCharacterCount = 0
    private var totalSegmentCount = 0

    init(
        now: Date,
        calendar: Calendar,
        status: ProviderStatusSummary,
        typingCharsPerSecond: Double
    ) {
        self.now = now
        self.calendar = calendar
        self.status = status
        self.typingCharsPerSecond = typingCharsPerSecond > 0
            ? typingCharsPerSecond
            : OverviewMetricsBuilder.defaultTypingCharsPerSecond
        let startOfToday = calendar.startOfDay(for: now)
        bucketDates = (0..<7).reversed().map {
            calendar.date(byAdding: .day, value: -$0, to: startOfToday) ?? startOfToday
        }
    }

    mutating func add(_ item: CaptureItem) {
        add(createdAt: item.createdAt, finalText: item.idiomatic, sourceText: item.sourceText)
    }

    mutating func add(createdAt: Date, finalText: String, sourceText: String?) {
        guard let text = OverviewMetricsBuilder.visibleText(
            finalText: finalText,
            sourceText: sourceText)
        else { return }

        let characterCount = text.count
        totalSegmentCount += 1
        totalCharacterCount += characterCount

        if calendar.isDate(createdAt, inSameDayAs: now) {
            todaySegmentCount += 1
            todayCharacterCount += characterCount
        }
        if let index = bucketDates.firstIndex(where: {
            calendar.isDate(createdAt, inSameDayAs: $0)
        }) {
            bucketSegmentCounts[index] += 1
            bucketCharacterCounts[index] += characterCount
        }
    }

    func metrics() -> OverviewMetrics {
        OverviewMetrics(
            todayCharacterCount: todayCharacterCount,
            todaySegmentCount: todaySegmentCount,
            totalSegmentCount: totalSegmentCount,
            estimatedTypingSecondsSaved: Double(totalCharacterCount) / typingCharsPerSecond,
            last7Days: bucketDates.indices.map {
                OverviewDayBucket(
                    date: bucketDates[$0],
                    segmentCount: bucketSegmentCounts[$0],
                    characterCount: bucketCharacterCounts[$0])
            },
            providerStatus: status)
    }
}
