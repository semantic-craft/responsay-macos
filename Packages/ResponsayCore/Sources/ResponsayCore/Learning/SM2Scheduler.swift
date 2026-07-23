import Foundation

public enum SM2Scheduler {
    public static let minimumEaseFactor = 1.3
    public static let defaultEaseFactor = 2.5
    /// Hard interval ceiling (100 years). Without it the ×ease growth overflows
    /// the Int32 the SQLite stores bind (`Int32(intervalDays)` traps) on the
    /// ~24th consecutive correct answer — reachable in minutes through the
    /// 加练 loop, which has no due gate — and the un-updated row then crashes
    /// every later answer (猎虫③ F1).
    public static let maximumIntervalDays = 36_500

    public static func schedule(
        _ card: ReviewCard,
        grade: ReviewGrade,
        reviewedAt: Date = Date()
    ) -> ReviewCard {
        schedule(card, quality: grade.rawValue, reviewedAt: reviewedAt)
    }

    public static func schedule(
        _ card: ReviewCard,
        quality: Int,
        reviewedAt: Date = Date()
    ) -> ReviewCard {
        let clampedQuality = max(0, min(5, quality))
        let adjustedEase = easeFactor(after: clampedQuality, current: card.easeFactor)
        let repetitions: Int
        let intervalDays: Int

        if clampedQuality < 3 {
            repetitions = 0
            intervalDays = 1
        } else {
            repetitions = card.repetitions + 1
            switch repetitions {
            case 1:
                intervalDays = 1
            case 2:
                intervalDays = 6
            default:
                intervalDays = min(
                    Self.maximumIntervalDays,
                    max(1, Int(round(Double(max(card.intervalDays, 1)) * adjustedEase))))
            }
        }

        return card.scheduled(
            dueAt: reviewedAt.addingTimeInterval(TimeInterval(intervalDays * 86_400)),
            intervalDays: intervalDays,
            repetitions: repetitions,
            easeFactor: adjustedEase)
    }

    private static func easeFactor(after quality: Int, current: Double) -> Double {
        let q = Double(quality)
        let penalty = (5 - q) * (0.08 + (5 - q) * 0.02)
        return max(minimumEaseFactor, current + (0.1 - penalty))
    }
}
