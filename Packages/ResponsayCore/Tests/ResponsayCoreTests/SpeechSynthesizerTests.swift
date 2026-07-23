import Testing
import Foundation
@testable import ResponsayCore

/// 201 — pure TTS synthesis boundary (`SpeechSynthesizer` / `SynthesizedSpeech` /
/// `TTSError`). Test standard T1 only — no engine, audio, or network.
struct SpeechSynthesizerTests {
    @Test func duration_isSamplesOverSampleRate() {
        let speech = SynthesizedSpeech(samples: [Float](repeating: 0, count: 24_000), sampleRate: 24_000)
        #expect(speech.duration == 1.0)
        let half = SynthesizedSpeech(samples: [Float](repeating: 0, count: 12_000), sampleRate: 24_000)
        #expect(half.duration == 0.5)
    }

    @Test func duration_guardsZeroSampleRate() {
        let speech = SynthesizedSpeech(samples: [0, 0, 0], sampleRate: 0)
        #expect(speech.duration == 0)
    }

    @Test func providerTiming_defaultsNil_forOnDeviceContract() {
        let speech = SynthesizedSpeech(samples: [0], sampleRate: 24_000)
        #expect(speech.providerTiming == nil)
    }

    @Test func ttsError_isEquatable_soCallSitesCanBranch() {
        #expect(TTSError.modelNotInstalled == .modelNotInstalled)
        #expect(TTSError.synthesisFailed("a") == .synthesisFailed("a"))
        #expect(TTSError.synthesisFailed("a") != .synthesisFailed("b"))
        #expect(TTSError.emptyText != .modelNotInstalled)
    }

    // MARK: - protocol is satisfiable + usable for downstream headless tests

    @Test func stubSynthesizer_returnsFixedDuration_andRecordsCalls() async throws {
        let stub = StubSynthesizer(secondsPerCall: 2.0, sampleRate: 24_000)
        let speech = try await stub.synthesize("hello")
        #expect(speech.sampleRate == 24_000)
        #expect(abs(speech.duration - 2.0) < 1e-9)
        #expect(stub.calls == ["hello"])
    }

    @Test func stubSynthesizer_throwsConfiguredFailure() async {
        let stub = StubSynthesizer(failure: .modelNotInstalled)
        await #expect(throws: TTSError.modelNotInstalled) {
            _ = try await stub.synthesize("hello")
        }
    }
}
