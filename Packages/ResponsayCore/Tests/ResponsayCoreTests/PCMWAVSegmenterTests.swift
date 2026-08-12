import Testing
import Foundation
@testable import ResponsayCore

/// Pins the batch-ASR "录音太长" fix: 16 kHz mono PCM is split into WAV segments
/// that each stay under the provider's per-request size budget, the cut points
/// prefer pauses over mid-word byte boundaries, and the WAV framing is
/// well-formed. The realtime path has no size limit; this only hardens the
/// batch fallback so it can never hard-fail again.
@Suite struct PCMWAVSegmenterTests {
    private let maxBytes = PCMWAVSegmenter.defaultMaxSegmentBytes
    private var maxSamples: Int { maxBytes / PCMWAVSegmenter.bytesPerSample }

    /// Speech-loud constant samples with a silent gap dropped in.
    private func loudSamples(count: Int, silentGap: Range<Int>? = nil) -> [Int16] {
        var samples = [Int16](repeating: 8_000, count: count)
        if let silentGap {
            for index in silentGap { samples[index] = 0 }
        }
        return samples
    }

    @Test func emptyAudioYieldsNoSegments() {
        #expect(PCMWAVSegmenter.planSegments(samples: []) == [])
        #expect(PCMWAVSegmenter.segmentedWAVs(samples: []).isEmpty)
    }

    @Test func shortAudioFitsInOneSegment() {
        let ranges = PCMWAVSegmenter.planSegments(samples: loudSamples(count: 16_000)) // 1 s
        #expect(ranges == [0..<16_000])
    }

    @Test func exactlyAtBudgetStaysOneSegment() {
        let ranges = PCMWAVSegmenter.planSegments(samples: loudSamples(count: maxSamples))
        #expect(ranges == [0..<maxSamples])
    }

    @Test func overBudgetSplitsIntoCoveringSegments() {
        // 2.5× the budget → contiguous, gap-free segments that cover everything,
        // each within the byte budget and none starved below half of it (the
        // silence search may only move a cut back by half a segment).
        let total = maxSamples * 2 + maxSamples / 2
        let ranges = PCMWAVSegmenter.planSegments(samples: loudSamples(count: total))
        #expect(ranges.first?.lowerBound == 0)
        #expect(ranges.last?.upperBound == total)
        for (a, b) in zip(ranges, ranges.dropFirst()) {
            #expect(a.upperBound == b.lowerBound)
        }
        for range in ranges {
            #expect(range.count <= maxSamples)
        }
        for range in ranges.dropLast() {
            #expect(range.count >= maxSamples / 2)
        }
    }

    @Test func cutLandsInsideASilentPause() {
        // One small-budget segment boundary with a 0.25 s silent gap inside the
        // search window: the cut must land in the gap, not at the byte boundary.
        let budget = 320_000                       // 160k samples = 10 s per segment
        let gap = 100_000..<104_000                // silence 6.25 s in, inside the window
        let samples = loudSamples(count: 240_000, silentGap: gap)
        let ranges = PCMWAVSegmenter.planSegments(samples: samples, maxSegmentBytes: budget)
        #expect(ranges.count == 2)
        let cut = ranges[0].upperBound
        #expect(gap.contains(cut))
        #expect(ranges[1] == cut..<240_000)
    }

    @Test func pauselessAudioStillSplitsWithinBudget() {
        // No silence anywhere (constant loud tone): the planner still makes
        // forward progress and every segment respects the budget.
        let budget = 320_000
        let perSegment = budget / PCMWAVSegmenter.bytesPerSample
        let samples = loudSamples(count: perSegment * 3 + 7)
        let ranges = PCMWAVSegmenter.planSegments(samples: samples, maxSegmentBytes: budget)
        #expect(ranges.first?.lowerBound == 0)
        #expect(ranges.last?.upperBound == samples.count)
        for (a, b) in zip(ranges, ranges.dropFirst()) {
            #expect(a.upperBound == b.lowerBound)
        }
        for range in ranges {
            #expect(range.count <= perSegment)
        }
    }

    /// The 15-minute listening ceiling (QuickCaptureViewModel.maxListeningDuration)
    /// must never produce a request any batch provider rejects: every planned
    /// segment plus WAV header stays under the tightest provider byte cap, so
    /// "录音太长" is unreachable from the segmented path.
    @Test func fifteenMinuteCaptureFitsEveryProviderCap() {
        let fifteenMinutes = 15 * 60 * PCMWAVSegmenter.sampleRate
        let ranges = PCMWAVSegmenter.planSegments(samples: [Int16](repeating: 0, count: fifteenMinutes))
        #expect(ranges.count == 5)
        #expect(ranges.first?.lowerBound == 0)
        #expect(ranges.last?.upperBound == fifteenMinutes)

        let tightestCap = [
            DirectMimoTranscriptionAPI.defaultMaxAudioBytes,
            DirectOpenAITranscriptionAPI.defaultMaxAudioBytes,
            DirectGeminiTranscriptionAPI.defaultMaxAudioBytes,
        ].min()!
        for range in ranges {
            let wavBytes = 44 + range.count * PCMWAVSegmenter.bytesPerSample
            #expect(wavBytes <= tightestCap)
        }
        #expect(44 + PCMWAVSegmenter.defaultMaxSegmentBytes <= tightestCap)
    }

    @Test func everySegmentStaysUnderRawBudget() {
        let samples = [Int16](repeating: 1234, count: maxSamples * 3 + 7)
        let wavs = PCMWAVSegmenter.segmentedWAVs(samples: samples)
        for wav in wavs {
            // header (44) + PCM payload must not exceed the budget + header.
            #expect(wav.count <= 44 + maxBytes)
        }
        // Reassembling the payloads loses nothing.
        let payloadBytes = wavs.map { $0.count - 44 }.reduce(0, +)
        #expect(payloadBytes == samples.count * PCMWAVSegmenter.bytesPerSample)
    }

    @Test func wavHeaderIsWellFormed() {
        let wav = PCMWAVSegmenter.wavData([0, 1, -1, 32767, -32768][...])
        #expect(wav.count == 44 + 5 * 2)                          // header + 5 samples
        #expect(Array(wav[0..<4]) == Array("RIFF".utf8))
        #expect(Array(wav[8..<12]) == Array("WAVE".utf8))
        #expect(Array(wav[36..<40]) == Array("data".utf8))
        // sample rate (little-endian UInt32 at offset 24) == 16000
        let rate = UInt32(wav[24]) | (UInt32(wav[25]) << 8) | (UInt32(wav[26]) << 16) | (UInt32(wav[27]) << 24)
        #expect(rate == 16_000)
        // bits per sample (offset 34) == 16, channels (offset 22) == 1
        #expect(wav[34] == 16 && wav[35] == 0)
        #expect(wav[22] == 1 && wav[23] == 0)
        // data chunk size (offset 40) == sampleCount * 2
        let dataSize = UInt32(wav[40]) | (UInt32(wav[41]) << 8) | (UInt32(wav[42]) << 16) | (UInt32(wav[43]) << 24)
        #expect(dataSize == 10)
    }

    @Test func samplesAreLittleEndianInPayload() {
        // 0x0102 → bytes [0x02, 0x01] at the start of the data chunk (offset 44).
        let wav = PCMWAVSegmenter.wavData([0x0102][...])
        #expect(wav[44] == 0x02)
        #expect(wav[45] == 0x01)
    }
}
