import Foundation

/// Splits 16 kHz / 16-bit / mono PCM into WAV segments that each stay under the
/// batch ASR per-request size limit, so the cloud short-clip path can never
/// hard-fail with "录音太长" again.
///
/// Background: `qwen3-asr-flash` (the batch path) caps input at **10 MB base64**
/// (verified against the Bailian ASR API reference). base64 inflates payloads by
/// ~4/3, so the raw budget is ~7.5 MB; we target a conservative 6 MB per segment.
/// The realtime WebSocket engines have no clip-size limit — this segmenter only
/// hardens the batch fallback. The audio downconversion that produces the Int16
/// samples lives in the platform (AVFoundation) layer; this type is pure so the
/// boundary math and WAV framing are unit-testable.
public enum PCMWAVSegmenter {
    public static let sampleRate = 16_000
    public static let bytesPerSample = 2

    /// Conservative raw-byte budget per segment, leaving headroom under the
    /// 10 MB *base64* limit (≈ 7.5 MB raw). 6 MB ≈ 187 s of 16 kHz mono PCM.
    public static let defaultMaxSegmentBytes = 6_000_000

    /// How far back from the hard byte boundary a cut may move to land in a
    /// pause. 10 s of speech virtually always contains at least one breath gap;
    /// the window is clamped to half the segment so a cut can never starve the
    /// next segment.
    public static let boundarySearchSamples = 10 * sampleRate

    /// Energy-scan granularity for the cut search. 100 ms is long enough that a
    /// minimum-energy frame is a genuine pause rather than a stop-consonant
    /// closure inside a word.
    public static let energyFrameSamples = sampleRate / 10

    /// Frame ranges that each fit within `maxSegmentBytes` of PCM payload.
    ///
    /// A cut at the raw byte boundary lands mid-word and mangles the words on
    /// both sides of the join, so each non-final cut is moved back to the
    /// middle of the quietest 100 ms frame within the last 10 s of the segment
    /// — for real speech that is a pause between words. When every frame is
    /// equally loud (tone, music) the latest minimum wins, keeping segments as
    /// full as possible.
    public static func planSegments(
        samples: [Int16],
        maxSegmentBytes: Int = defaultMaxSegmentBytes
    ) -> [Range<Int>] {
        guard !samples.isEmpty else { return [] }
        let maxSamples = max(1, maxSegmentBytes / bytesPerSample)
        var ranges: [Range<Int>] = []
        var start = 0
        while start < samples.count {
            let hardEnd = start + maxSamples
            guard hardEnd < samples.count else {
                ranges.append(start..<samples.count)
                break
            }
            let cut = quietestCut(
                in: samples,
                before: hardEnd,
                window: min(boundarySearchSamples, maxSamples / 2))
            ranges.append(start..<cut)
            start = cut
        }
        return ranges
    }

    /// Midpoint of the lowest-energy frame in `[hardEnd - window, hardEnd)`,
    /// or `hardEnd` itself when the window is too small to hold one frame.
    private static func quietestCut(in samples: [Int16], before hardEnd: Int, window: Int) -> Int {
        guard window >= energyFrameSamples else { return hardEnd }
        var bestStart = hardEnd - energyFrameSamples
        var bestEnergy = Int64.max
        var frameStart = hardEnd - window
        while frameStart + energyFrameSamples <= hardEnd {
            var energy: Int64 = 0
            for index in frameStart..<(frameStart + energyFrameSamples) {
                let sample = Int64(samples[index])
                energy += sample * sample
            }
            if energy <= bestEnergy {
                bestEnergy = energy
                bestStart = frameStart
            }
            frameStart += energyFrameSamples
        }
        return bestStart + energyFrameSamples / 2
    }

    /// Wrap a slice of 16 kHz mono Int16 samples in a canonical 44-byte PCM WAV.
    public static func wavData(_ samples: ArraySlice<Int16>) -> Data {
        let dataByteCount = samples.count * bytesPerSample
        var data = Data(capacity: 44 + dataByteCount)
        data.append(contentsOf: Array("RIFF".utf8))
        appendLE32(&data, UInt32(36 + dataByteCount))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        appendLE32(&data, 16)                                    // PCM fmt chunk size
        appendLE16(&data, 1)                                     // audio format = PCM
        appendLE16(&data, 1)                                     // channels = mono
        appendLE32(&data, UInt32(sampleRate))
        appendLE32(&data, UInt32(sampleRate * bytesPerSample))   // byte rate
        appendLE16(&data, UInt16(bytesPerSample))                // block align
        appendLE16(&data, 16)                                    // bits per sample
        data.append(contentsOf: Array("data".utf8))
        appendLE32(&data, UInt32(dataByteCount))
        for sample in samples { appendLE16(&data, UInt16(bitPattern: sample)) }
        return data
    }

    /// WAV segments covering all samples, each ≤ `maxSegmentBytes` of PCM payload.
    public static func segmentedWAVs(
        samples: [Int16],
        maxSegmentBytes: Int = defaultMaxSegmentBytes
    ) -> [Data] {
        planSegments(samples: samples, maxSegmentBytes: maxSegmentBytes)
            .map { wavData(samples[$0]) }
    }

    private static func appendLE16(_ data: inout Data, _ value: UInt16) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
    }

    private static func appendLE32(_ data: inout Data, _ value: UInt32) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8((value >> 16) & 0xff))
        data.append(UInt8((value >> 24) & 0xff))
    }
}
