import Testing
import Foundation
@testable import ResponsayCore

/// 194 — read-aloud composer: chunk → synth → per-chunk proportional align →
/// offset + concatenate. Test standard T1 (StubSynthesizer, fully deterministic).
struct ReadAloudComposerTests {
    /// Long sentences so the default policy keeps them as separate chunks (no merge).
    private let multiChunkText =
        "The trivial chieftain called for the boy in the early morning light. " +
        "He presented him with fifty pieces of carefully counted gold. " +
        "The boy bowed deeply and accepted the unexpected and generous gift."

    private let composer = ReadAloudComposer()

    @Test func emptyTextYieldsEmpty() async throws {
        let stub = StubSynthesizer()
        let composed = try await composer.compose("   ", using: stub)
        #expect(composed.chunks.isEmpty)
        #expect(composed.timeline.isEmpty)
        #expect(composed.totalDuration == 0)
        #expect(stub.calls.isEmpty)
    }

    @Test func singleChunkMatchesDirectProportionalAlign() async throws {
        let text = "Hello there world."
        let stub = StubSynthesizer(secondsPerCall: 1.5)
        let composed = try await composer.compose(text, using: stub)
        // One chunk → offset 0 → timeline equals a direct proportional align.
        #expect(composed.chunks.count == 1)
        let direct = DefaultWordTimingAligner().align(
            text: text, providerTiming: nil, audioDuration: 1.5)
        #expect(composed.timeline.map(\.text) == direct.map(\.text))
        #expect(composed.timeline.first?.startTime == 0)
        #expect(abs((composed.timeline.last?.endTime ?? -1) - 1.5) < 1e-9)
    }

    @Test func concatenatesChunksContiguouslyWithOffsets() async throws {
        let stub = StubSynthesizer(secondsPerCall: 2.0)
        // Derive the expected chunking from the same chunker the composer uses.
        let expectedChunks = TTSTextChunker().chunk(multiChunkText, policy: .default)
        try #require(expectedChunks.count >= 2, "need a multi-chunk fixture")
        let composed = try await composer.compose(multiChunkText, using: stub)

        #expect(composed.chunks.count == expectedChunks.count)
        #expect(stub.calls.count == expectedChunks.count)
        // Total = sum of per-chunk durations.
        #expect(abs(composed.totalDuration - Double(expectedChunks.count) * 2.0) < 1e-9)

        // Timeline is contiguous + non-decreasing, starts at 0, ends at total.
        #expect(composed.timeline.first?.startTime == 0)
        #expect(abs((composed.timeline.last?.endTime ?? -1) - composed.totalDuration) < 1e-9)
        for i in 1..<composed.timeline.count {
            #expect(composed.timeline[i].startTime >= composed.timeline[i - 1].startTime - 1e-9)
            #expect(composed.timeline[i].startTime >= composed.timeline[i - 1].endTime - 1e-9)
        }
        // Every word stays within [0, total].
        for word in composed.timeline {
            #expect(word.startTime >= -1e-9)
            #expect(word.endTime <= composed.totalDuration + 1e-9)
        }
        // A word exists at each chunk's start offset (offset 2.0, 4.0, …).
        for k in 1..<expectedChunks.count {
            let offset = Double(k) * 2.0
            #expect(composed.timeline.contains { abs($0.startTime - offset) < 1e-6 })
        }
    }

    @Test func speedForwardsToSynthAndScalesTimeline() async throws {
        let stub = StubSynthesizer(secondsPerCall: 1.0)  // stub scales duration by 1/speed
        let chunks = TTSTextChunker().chunk(multiChunkText, policy: .default)
        let slow = try await composer.compose(multiChunkText, using: stub, speed: 0.5)
        // 0.5× → each chunk lasts 2.0s; total scales accordingly, timeline stays in sync.
        #expect(abs(slow.totalDuration - Double(chunks.count) * 2.0) < 1e-9)
        #expect(abs((slow.timeline.last?.endTime ?? -1) - slow.totalDuration) < 1e-9)
        #expect(stub.speeds.allSatisfy { $0 == 0.5 })
    }

    @Test func synthFailurePropagates() async {
        let stub = StubSynthesizer(failure: .modelNotInstalled)
        await #expect(throws: TTSError.modelNotInstalled) {
            _ = try await composer.compose(multiChunkText, using: stub)
        }
    }

    @Test func wordCountEqualsSumOfChunkWords() async throws {
        let stub = StubSynthesizer(secondsPerCall: 1.0)
        let chunks = TTSTextChunker().chunk(multiChunkText, policy: .default)
        let expectedWords = chunks.reduce(0) {
            $0 + DefaultWordTimingAligner().align(
                text: $1.text, providerTiming: nil, audioDuration: 1.0).count
        }
        let composed = try await composer.compose(multiChunkText, using: stub)
        #expect(composed.timeline.count == expectedWords)
    }
}
