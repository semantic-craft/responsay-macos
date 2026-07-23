import Foundation

/// The deterministic post-ASR pipeline every provider's final transcript funnels through, gated by
/// the engine's `SpeechCaptureCapability`. Pure and synchronous, so it is unit-testable without a
/// mic, a network, or the app target — the router calls it, then applies its async, default-off LLM
/// correction tier on top.
public enum SpeechTranscriptFinalizer {
    /// Returns the hard-match-enforced transcript, or `nil` when it was a biasing-list echo that must
    /// be dropped.
    ///
    /// - The echo filter (ADR-0011 / the 1.3.29 guard) runs **only** when `capability.needsEchoFilter`.
    ///   On-device engines send no text biasing hint, so a legitimate comma-list dictation
    ///   ("Westlaw, SSRN") is no longer mis-dropped by them.
    /// - Hard-match enforcement is universal (every engine).
    public static func enforce(
        _ transcript: String,
        capability: SpeechCaptureCapability,
        sets: HotwordBiasingSets,
        echoTerms: [String]
    ) -> String? {
        if capability.needsEchoFilter, HotwordEchoFilter.isEcho(transcript, terms: echoTerms) {
            return nil
        }
        return sets.enforce(transcript).text
    }
}
