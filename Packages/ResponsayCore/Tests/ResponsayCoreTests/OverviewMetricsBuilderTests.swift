import Testing
import Foundation
@testable import ResponsayCore

/// 151 — Overview metrics store.
/// Verification: day rollover; empty data; provider-status mapping.
struct OverviewMetricsBuilderTests {
    private let builder = OverviewMetricsBuilder()

    /// Deterministic UTC Gregorian calendar for stable day math.
    private var utc: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d; comps.hour = h
        return utc.date(from: comps)!
    }

    private func item(_ when: Date, idiomatic: String = "", source: String? = "hello") -> CaptureItem {
        CaptureItem(createdAt: when, sourceText: source, language: "en-US", idiomatic: idiomatic, reasons: [])
    }

    @Test func emptyData_isAllZero() {
        let m = builder.build(from: [], now: date(2026, 6, 7), calendar: utc)
        #expect(m.todayCharacterCount == 0)
        #expect(m.todaySegmentCount == 0)
        #expect(m.totalSegmentCount == 0)
        #expect(m.last7Days.count == 7)
        #expect(m.last7Days.allSatisfy { $0.segmentCount == 0 })
    }

    @Test func todayCounts_onlyTodayItems() {
        let now = date(2026, 6, 7)
        let items = [
            item(date(2026, 6, 7), idiomatic: "twelve chars"),     // today, 12 chars
            item(date(2026, 6, 7), source: "hi"),                  // today, 2 chars
            item(date(2026, 6, 6), idiomatic: "yesterday stuff"),  // not today
        ]
        let m = builder.build(from: items, now: now, calendar: utc)
        #expect(m.todaySegmentCount == 2)
        #expect(m.todayCharacterCount == 14)        // 12 + 2
        #expect(m.totalSegmentCount == 3)
    }

    @Test func dayRollover_bucketsAlignToCalendarDays() {
        let now = date(2026, 6, 7, 23)              // late in the day
        let items = [
            item(date(2026, 6, 7, 1)),              // today (different hour)
            item(date(2026, 6, 6, 9)),
            item(date(2026, 6, 6, 22)),
            item(date(2026, 6, 1)),                 // 6 days ago → still in window
            item(date(2026, 5, 31)),                // 7 days ago → out of window
        ]
        let m = builder.build(from: items, now: now, calendar: utc)
        #expect(m.last7Days.count == 7)
        // oldest → newest; last bucket is today
        #expect(m.last7Days.last?.segmentCount == 1)
        // the 2026-06-06 bucket holds two items
        let jun6 = m.last7Days.first { utc.isDate($0.date, inSameDayAs: self.date(2026, 6, 6)) }
        #expect(jun6?.segmentCount == 2)
        // the 7-days-ago item is excluded from all buckets
        let total7 = m.last7Days.reduce(0) { $0 + $1.segmentCount }
        #expect(total7 == 4)
    }

    @Test func typingSecondsSaved_scalesWithCharacters() {
        let now = date(2026, 6, 7)
        let items = [item(now, idiomatic: String(repeating: "x", count: 35))]
        let m = builder.build(from: items, now: now, calendar: utc, typingCharsPerSecond: 3.5)
        #expect(m.estimatedTypingSecondsSaved == 10.0)   // 35 / 3.5
    }

    @Test func optionalSource_countsApprovedFinalAndTreatsMissingTextAsZero() {
        let now = date(2026, 6, 7)
        let items = [
            item(now, idiomatic: "approved", source: nil),
            item(now, idiomatic: "", source: nil),
            item(now, idiomatic: "", source: "raw"),
        ]

        let metrics = builder.build(from: items, now: now, calendar: utc)

        #expect(metrics.todayCharacterCount == 11)
        #expect(metrics.totalSegmentCount == 3)
        #expect(metrics.last7Days.last?.segmentCount == 3)
        #expect(metrics.last7Days.last?.characterCount == 11)
    }

    // MARK: - provider-status mapping

    @Test func providerStatus_mapping() {
        #expect(ProviderStatus.from(isConfigured: false, isHealthy: nil) == .notConfigured)
        #expect(ProviderStatus.from(isConfigured: true, isHealthy: nil) == .unknown)
        #expect(ProviderStatus.from(isConfigured: true, isHealthy: true) == .ready)
        #expect(ProviderStatus.from(isConfigured: true, isHealthy: false) == .error)
    }

    @Test func providerStatus_passedThroughToMetrics() {
        let status = ProviderStatusSummary(asr: .ready, llm: .ready, tts: .notConfigured)
        let m = builder.build(from: [], now: date(2026, 6, 7), calendar: utc, status: status)
        #expect(m.providerStatus.tts == .notConfigured)
        #expect(m.providerStatus.asr == .ready)
    }
}
