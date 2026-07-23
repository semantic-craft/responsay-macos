import Testing
import Foundation
@testable import ResponsayCore

/// 136 — read/follow/repeat playback timeline.
struct ReadAloudTimelineTests {
    @Test func buildsWordOrderedTimeline_withGroupGaps() {
        let timeline = ReadAloudTimeline.build(.holdsUp, secondsPerSyllable: 0.3, groupGap: 0.2)
        let words = ProsodyAnalysis.holdsUp.thoughtGroups.flatMap { $0.words }
        #expect(timeline.count == words.count)
        #expect(timeline.first?.startTime == 0)
        // within group 1 the words are contiguous (no gap)
        #expect(timeline[1].startTime == timeline[0].endTime)
        // a gap separates the two thought groups (group2 starts after group1 end + gap)
        let group1Count = ProsodyAnalysis.holdsUp.thoughtGroups[0].words.count
        let g1End = timeline[group1Count - 1].endTime
        #expect(timeline[group1Count].startTime > g1End)            // gap inserted
        #expect(timeline[group1Count].startTime == g1End + 0.2)
    }

    @Test func durationScalesWithSyllables() {
        // "conclusion" (3 syllables) lasts 3× a 1-syllable word.
        let timeline = ReadAloudTimeline.build(.holdsUp, secondsPerSyllable: 0.3, groupGap: 0)
        let conclusion = timeline.first { $0.text == "conclusion" }!
        #expect(abs((conclusion.endTime - conclusion.startTime) - 0.9) < 0.0001)
    }

    @Test func activeIndex_resolvesByTime() {
        let timeline = ReadAloudTimeline.build(.sample, secondsPerSyllable: 0.3, groupGap: 0)
        #expect(ReadAloudTimeline.activeIndex(at: 0.0, in: timeline) == 0)
        let mid = (timeline[1].startTime + timeline[1].endTime) / 2
        #expect(ReadAloudTimeline.activeIndex(at: mid, in: timeline) == 1)
        let past = ReadAloudTimeline.totalDuration(timeline) + 1
        #expect(ReadAloudTimeline.activeIndex(at: past, in: timeline) == nil)
    }
}

/// 134 — AVAudioEngine prefetch scheduling.
struct AudioChunkSchedulerTests {
    private let scheduler = AudioChunkScheduler()

    @Test func scheduleIsSeamless() {
        let segments = scheduler.schedule(durations: [1.0, 2.0, 0.5])
        #expect(segments[0].startOffset == 0)
        #expect(segments[1].startOffset == segments[0].endOffset)   // no gap/overlap
        #expect(segments[2].startOffset == segments[1].endOffset)
        #expect(segments.last?.endOffset == 3.5)
    }

    @Test func totalDuration_sumsChunks() {
        #expect(scheduler.totalDuration(durations: [1.0, 2.0, 0.5]) == 3.5)
    }

    @Test func prefetchWindow_defaultsToTwoAhead() {
        // playing chunk 1, lookAhead 2 → {1,2,3}
        #expect(scheduler.prefetchWindow(playingIndex: 1, count: 6) == [1, 2, 3])
    }

    @Test func prefetchWindow_clampsAtEnd() {
        #expect(scheduler.prefetchWindow(playingIndex: 4, count: 5) == [4])  // last chunk, nothing ahead
        #expect(scheduler.prefetchWindow(playingIndex: 0, count: 0).isEmpty)
    }

    @Test func customLookAhead() {
        let s = AudioChunkScheduler(lookAhead: 1)
        #expect(s.prefetchWindow(playingIndex: 0, count: 5) == [0, 1])
    }
}
