import Foundation
import Testing
@testable import ResponsayCore

// 猎虫③ F1 — the scheduler had no interval ceiling: ×2.5 growth overflowed the
// Int32 the SQLite stores bind on the ~24th consecutive correct answer (trap →
// crash, and the stuck row crashed every later answer). These pin the ceiling
// and, while the file exists, the ease floor that previously had no direct test.
struct SM2SchedulerTests {

    private func makeCard() -> ReviewCard {
        ReviewCard(
            createdAt: Date(timeIntervalSince1970: 0),
            sourceText: "q", language: "en-US", idiomatic: "a", reasons: [],
            dueAt: Date(timeIntervalSince1970: 0))
    }

    @Test func longCorrectStreakStaysWithinInt32AndCeiling() {
        var card = makeCard()
        for _ in 0..<40 {
            card = SM2Scheduler.schedule(card, grade: .good, reviewedAt: Date(timeIntervalSince1970: 0))
            #expect(card.intervalDays <= SM2Scheduler.maximumIntervalDays)
            #expect(Int64(card.intervalDays) <= Int64(Int32.max))
        }
        #expect(card.intervalDays == SM2Scheduler.maximumIntervalDays)
    }

    @Test func easeFloorIsPinnedAt1_3() {
        var card = makeCard()
        for _ in 0..<20 {
            card = SM2Scheduler.schedule(card, quality: 0, reviewedAt: Date(timeIntervalSince1970: 0))
        }
        #expect(card.easeFactor >= SM2Scheduler.minimumEaseFactor)
        #expect(abs(card.easeFactor - SM2Scheduler.minimumEaseFactor) < 0.0001)
    }

    @Test func failResetsToOneDay() {
        var card = makeCard()
        for _ in 0..<5 { card = SM2Scheduler.schedule(card, grade: .good, reviewedAt: Date(timeIntervalSince1970: 0)) }
        card = SM2Scheduler.schedule(card, quality: 1, reviewedAt: Date(timeIntervalSince1970: 0))
        #expect(card.intervalDays == 1)
        #expect(card.repetitions == 0)
    }
}
