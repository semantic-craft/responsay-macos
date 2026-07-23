import Foundation

// MARK: - 136 read/follow/repeat — playback timeline (device-independent core)
//
// Builds a word-level timeline for the whole utterance so a player can drive
// word highlight on the stave. Until real TTS word timing (135 provider path)
// is wired, the duration is *estimated* from syllable count; the highlight
// mechanism is identical when real timings replace the estimate.

public enum ReadAloudTimeline {
    /// Estimated speaking time per syllable (GA, unhurried practice pace).
    public static let secondsPerSyllable = 0.32
    /// Silent gap inserted between thought groups.
    public static let groupGap = 0.25

    /// Flatten `analysis` into an ordered word timeline. Words are contiguous
    /// within a thought group; a `groupGap` of silence separates groups.
    public static func build(
        _ analysis: ProsodyAnalysis,
        secondsPerSyllable: Double = ReadAloudTimeline.secondsPerSyllable,
        groupGap: Double = ReadAloudTimeline.groupGap
    ) -> [TimedWord] {
        var words: [TimedWord] = []
        var cursor: TimeInterval = 0
        for (groupIndex, group) in analysis.thoughtGroups.enumerated() {
            if groupIndex > 0 { cursor += groupGap }
            for word in group.words {
                let syllables = max(1, word.syllables.count)
                let duration = Double(syllables) * secondsPerSyllable
                words.append(TimedWord(text: word.text, startTime: cursor, endTime: cursor + duration))
                cursor += duration
            }
        }
        return words
    }

    /// Total speaking time for a built timeline.
    public static func totalDuration(_ timeline: [TimedWord]) -> TimeInterval {
        timeline.last?.endTime ?? 0
    }

    /// The word index active at `time` (drives highlight). `nil` before the
    /// first word, in an inter-group gap, or after the end.
    public static func activeIndex(at time: TimeInterval, in timeline: [TimedWord]) -> Int? {
        for (index, word) in timeline.enumerated() where time >= word.startTime && time < word.endTime {
            return index
        }
        return nil
    }
}
