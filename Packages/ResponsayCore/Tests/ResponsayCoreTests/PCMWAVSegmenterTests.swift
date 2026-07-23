import Testing
import Foundation
@testable import ResponsayCore

/// Pins the batch-ASR "录音太长" fix: 16 kHz mono PCM is split into WAV segments
/// that each stay under the provider's per-request size budget, and the WAV
/// framing is well-formed. The realtime path has no size limit; this only
/// hardens the batch fallback so it can never hard-fail again.
@Suite struct PCMWAVSegmenterTests {
    private let maxBytes = PCMWAVSegmenter.defaultMaxSegmentBytes
    private var maxSamples: Int { maxBytes / PCMWAVSegmenter.bytesPerSample }

    @Test func emptyAudioYieldsNoSegments() {
        #expect(PCMWAVSegmenter.planSegments(sampleCount: 0) == [])
        #expect(PCMWAVSegmenter.segmentedWAVs(samples: []).isEmpty)
    }

    @Test func shortAudioFitsInOneSegment() {
        let ranges = PCMWAVSegmenter.planSegments(sampleCount: 16_000) // 1 s
        #expect(ranges == [0..<16_000])
    }

    @Test func exactlyAtBudgetStaysOneSegment() {
        let ranges = PCMWAVSegmenter.planSegments(sampleCount: maxSamples)
        #expect(ranges.count == 1)
        #expect(ranges.first == 0..<maxSamples)
    }

    @Test func overBudgetSplitsIntoCoveringSegments() {
        // 2.5× the budget → 3 contiguous, gap-free segments that cover everything.
        let total = maxSamples * 2 + maxSamples / 2
        let ranges = PCMWAVSegmenter.planSegments(sampleCount: total)
        #expect(ranges.count == 3)
        #expect(ranges.first?.lowerBound == 0)
        #expect(ranges.last?.upperBound == total)
        // contiguous, no gaps/overlaps
        for (a, b) in zip(ranges, ranges.dropFirst()) {
            #expect(a.upperBound == b.lowerBound)
        }
        // every non-final segment is exactly the budget
        for range in ranges.dropLast() {
            #expect(range.count == maxSamples)
        }
    }

    @Test func everySegmentStaysUnderRawBudget() {
        let samples = [Int16](repeating: 1234, count: maxSamples * 3 + 7)
        let wavs = PCMWAVSegmenter.segmentedWAVs(samples: samples)
        #expect(wavs.count == 4)
        for wav in wavs {
            // header (44) + PCM payload must not exceed the budget + header.
            #expect(wav.count <= 44 + maxBytes)
        }
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
