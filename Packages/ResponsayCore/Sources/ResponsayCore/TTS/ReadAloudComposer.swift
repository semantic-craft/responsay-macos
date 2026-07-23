import Foundation

/// One utterance ready to play: per-chunk audio (in order) plus a single
/// word-highlight timeline whose times are absolute over the whole utterance
/// (issue 194). The player schedules `chunks` gaplessly; the highlighter reads
/// `timeline` against the player's elapsed time.
public struct ComposedReadAloud: Sendable, Equatable {
    public let chunks: [SynthesizedSpeech]
    public let timeline: [TimedWord]
    public let totalDuration: TimeInterval

    public init(chunks: [SynthesizedSpeech], timeline: [TimedWord], totalDuration: TimeInterval) {
        self.chunks = chunks
        self.timeline = timeline
        self.totalDuration = totalDuration
    }

    public var hasPlayableAudio: Bool {
        totalDuration.isFinite && totalDuration > 0 && !chunks.isEmpty
            && chunks.allSatisfy { chunk in
                chunk.sampleRate > 0
                    && chunk.duration.isFinite
                    && chunk.duration > 0
                    && chunk.samples.allSatisfy(\.isFinite)
                    && chunk.samples.contains { $0 != 0 }
            }
    }
}

/// Turns text into playable audio + a word-highlight timeline using the proven
/// **per-sentence** approach (issue 194 / spec Revision 1): chunk → synth each
/// chunk → proportional word timing per chunk → offset each chunk's timeline by its
/// playback start and concatenate. Per-sentence keeps proportional-timing error
/// bounded to one sentence (Kokoro ONNX exposes no native word alignment) and lets
/// the first sentence play while later ones synthesize.
///
/// Pure and engine-agnostic: it speaks to `SpeechSynthesizer` (201), `TTSTextChunker`
/// (133), `AudioChunkScheduler` (134), and `WordTimingAligner` (135) — all injectable,
/// so it is fully headless-testable with a stub synthesizer.
public struct ReadAloudComposer: Sendable {
    private let chunker: TTSTextChunker
    private let aligner: WordTimingAligner
    private let scheduler: AudioChunkScheduler
    private let chunkingPolicy: TTSChunkingPolicy

    public init(
        chunker: TTSTextChunker = TTSTextChunker(),
        aligner: WordTimingAligner = DefaultWordTimingAligner(),
        scheduler: AudioChunkScheduler = AudioChunkScheduler(),
        chunkingPolicy: TTSChunkingPolicy = .default
    ) {
        self.chunker = chunker
        self.aligner = aligner
        self.scheduler = scheduler
        self.chunkingPolicy = chunkingPolicy
    }

    /// Synthesize `text` chunk-by-chunk and build the concatenated timeline.
    /// - Parameter speed: speaking rate forwarded to the synthesizer (issue 198);
    ///   the timeline is built from the *produced* audio duration, so it stays in sync
    ///   at any rate with no extra bookkeeping.
    /// - Throws: whatever `synthesizer.synthesize` throws (e.g. `TTSError`); callers
    ///   that want a no-audio fallback should catch and fall back to an estimate.
    public func compose(
        _ text: String,
        using synthesizer: any SpeechSynthesizer,
        speed: Double = 1.0
    ) async throws -> ComposedReadAloud {
        let blocks = chunker.chunk(text, policy: chunkingPolicy)
            .sorted { $0.order < $1.order }
        guard !blocks.isEmpty else {
            return ComposedReadAloud(chunks: [], timeline: [], totalDuration: 0)
        }

        // 1. Synthesize each chunk (sequential — keeps memory bounded and order stable;
        //    a future optimization can pipeline synth ahead of playback).
        var chunkAudio: [SynthesizedSpeech] = []
        chunkAudio.reserveCapacity(blocks.count)
        for block in blocks {
            chunkAudio.append(try await synthesizer.synthesize(block.text, speed: speed))
        }

        // 2. Lay chunks end-to-end → per-chunk start offsets (134).
        let durations = chunkAudio.map(\.duration)
        let segments = scheduler.schedule(durations: durations)
        let total = scheduler.totalDuration(durations: durations)

        // 3. Align each chunk locally (135, per-sentence), shift by its start offset,
        //    and concatenate into one absolute-time timeline.
        var timeline: [TimedWord] = []
        for (index, block) in blocks.enumerated() {
            let audio = chunkAudio[index]
            let local = aligner.align(
                text: block.text,
                providerTiming: audio.providerTiming,
                audioDuration: audio.duration)
            let offset = segments[index].startOffset
            timeline.append(contentsOf: local.map {
                TimedWord(
                    text: $0.text,
                    startTime: $0.startTime + offset,
                    endTime: $0.endTime + offset,
                    confidence: $0.confidence)
            })
        }

        return ComposedReadAloud(chunks: chunkAudio, timeline: timeline, totalDuration: total)
    }
}
