import Testing
@testable import ResponsayCore

struct SpeechTranscriptFinalizerTests {
    // Empty hard-match sets → enforce() is identity, so we observe only the capability-gated echo filter.
    private func emptySets() -> HotwordBiasingSets {
        HotwordBiasingSets(weakPrompt: [], hardMatchUser: [], hardMatchSeed: [])
    }
    private let echoTerms = ["Westlaw", "SSRN", "arXiv"]
    private let echoShaped = "Westlaw, SSRN"   // ≥2 known terms, comma-separated = a biasing-list echo

    @Test func cloudEngineDropsBiasingListEcho() {
        let cloud = SpeechCaptureCapability(needsEchoFilter: true)
        #expect(SpeechTranscriptFinalizer.enforce(
            echoShaped, capability: cloud, sets: emptySets(), echoTerms: echoTerms) == nil)
    }

    @Test func onDeviceEngineKeepsLegitimateTermListDictation() {
        // The regression guard for this task: the SAME echo-shaped transcript from an on-device engine
        // (needsEchoFilter == false) must NOT be dropped — it can't have echoed anything.
        let onDevice = SpeechCaptureCapability(needsEchoFilter: false)
        #expect(SpeechTranscriptFinalizer.enforce(
            echoShaped, capability: onDevice, sets: emptySets(), echoTerms: echoTerms) == echoShaped)
    }

    @Test func realProseIsNeverDroppedEvenOnCloud() {
        let cloud = SpeechCaptureCapability(needsEchoFilter: true)
        let prose = "Let's meet about Westlaw tomorrow."
        #expect(SpeechTranscriptFinalizer.enforce(
            prose, capability: cloud, sets: emptySets(), echoTerms: echoTerms) == prose)
    }

    @Test func defaultCapabilityDoesNotEchoFilter() {
        // The protocol-extension default (on-device posture) must not run the echo filter.
        #expect(SpeechCaptureCapability().needsEchoFilter == false)
        #expect(SpeechTranscriptFinalizer.enforce(
            echoShaped, capability: .init(), sets: emptySets(), echoTerms: echoTerms) == echoShaped)
    }
}
