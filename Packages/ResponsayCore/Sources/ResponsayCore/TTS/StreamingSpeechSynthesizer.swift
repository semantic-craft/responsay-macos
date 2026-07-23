import Foundation

/// A TTS engine that emits audio **as it is synthesized** (issue 197) rather than
/// one whole-utterance blob — for low time-to-first-audio. Each element is a
/// contiguous chunk in playback order; concatenating them yields the full audio.
/// Only Qwen's realtime WebSocket offers this among the surveyed providers.
public protocol StreamingSpeechSynthesizer: Sendable {
    func stream(_ text: String, speed: Double) -> AsyncThrowingStream<SynthesizedSpeech, Error>
}

public extension StreamingSpeechSynthesizer {
    /// Collect a stream into a single `SynthesizedSpeech` (concatenated samples),
    /// so a streaming engine can also feed the whole-utterance pipeline (194) as a
    /// fallback. The sample rate is taken from the first chunk.
    func collected(_ text: String, speed: Double = 1.0) async throws -> SynthesizedSpeech {
        var samples: [Float] = []
        var sampleRate = 24_000
        var first = true
        for try await chunk in stream(text, speed: speed) {
            if first { sampleRate = chunk.sampleRate; first = false }
            samples.append(contentsOf: chunk.samples)
        }
        return SynthesizedSpeech(samples: samples, sampleRate: sampleRate, providerTiming: nil)
    }
}
