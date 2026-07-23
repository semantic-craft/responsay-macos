import Foundation
@testable import ResponsayCore

/// Deterministic `SpeechSynthesizer` test double (test standard T1): returns fixed
/// audio per text, or throws, with no real engine/audio/network. Reused by the 201
/// protocol tests and the 194 pipeline tests.
final class StubSynthesizer: SpeechSynthesizer, @unchecked Sendable {
    /// Per-call duration in seconds; the stub fabricates `duration * sampleRate`
    /// silent samples so `SynthesizedSpeech.duration` is exactly `duration`.
    let secondsPerCall: TimeInterval
    let sampleRate: Int
    let providerTiming: [TimedWord]?
    /// When set, every call throws this instead of returning audio.
    let failure: TTSError?
    /// Records the texts passed to `synthesize`, in order.
    private(set) var calls: [String] = []

    init(
        secondsPerCall: TimeInterval = 1.0,
        sampleRate: Int = 24_000,
        providerTiming: [TimedWord]? = nil,
        failure: TTSError? = nil
    ) {
        self.secondsPerCall = secondsPerCall
        self.sampleRate = sampleRate
        self.providerTiming = providerTiming
        self.failure = failure
    }

    /// Records each call's text + speed. Duration scales by 1/speed (slower speed →
    /// longer audio), mirroring real synth so 198 timeline assertions are exact.
    private(set) var speeds: [Double] = []

    func synthesize(_ text: String, speed: Double) async throws -> SynthesizedSpeech {
        calls.append(text)
        speeds.append(speed)
        if let failure { throw failure }
        let scaled = secondsPerCall / max(0.5, min(2.0, speed))
        let count = max(0, Int((scaled * Double(sampleRate)).rounded()))
        return SynthesizedSpeech(
            samples: [Float](repeating: 0, count: count),
            sampleRate: sampleRate,
            providerTiming: providerTiming
        )
    }
}
