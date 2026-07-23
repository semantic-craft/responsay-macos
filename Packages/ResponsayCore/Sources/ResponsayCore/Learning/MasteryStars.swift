import Foundation

/// Single source of truth for the 1–5 mastery rating derived from SM-2 state.
/// Shared by `ReviewCard` and `DrillProgress` so the rule lives in one place.
public enum MasteryStars {
    public static func rating(repetitions: Int, easeFactor: Double) -> Int {
        let repetitionScore = min(4, max(0, repetitions))
        let easeBonus = easeFactor >= 2.8 ? 1 : 0
        return min(5, max(1, repetitionScore + easeBonus + 1))
    }
}
