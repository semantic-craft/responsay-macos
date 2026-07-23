import Testing
import Foundation
@testable import ResponsayCore

/// Pins the typed failure classification (issue 087 items 8.1 + 9): raw provider
/// strings and URL errors map to actionable categories, and fallback-eligibility
/// is correct (terminal failures must not trigger a pointless on-device retry).
@Suite struct CaptureFailureTests {
    @Test func classifiesAudioTooLong() {
        #expect(CaptureFailure.classify(message: "录音太长,云端短句识别上限约 10MB(base64 后)。") == .audioTooLong)
    }

    @Test func classifiesNotAuthorized() {
        #expect(CaptureFailure.classify(message: "麦克风未授权。请到系统设置开启。") == .notAuthorized)
    }

    @Test func classifiesTimeoutMessage() {
        #expect(CaptureFailure.classify(message: "Realtime ASR timed out waiting for session.finished.") == .timeout)
    }

    @Test func classifiesUrlTimeout() {
        #expect(CaptureFailure.classify(URLError(.timedOut)) == .timeout)
    }

    @Test func classifiesUrlNetwork() {
        #expect(CaptureFailure.classify(URLError(.notConnectedToInternet)) == .network)
    }

    @Test func unknownBecomesProvider() {
        #expect(CaptureFailure.classify(message: "weird model echo") == .provider("weird model echo"))
    }

    @Test func fallbackEligibility() {
        #expect(CaptureFailure.network.isFallbackEligible)
        #expect(CaptureFailure.timeout.isFallbackEligible)
        #expect(!CaptureFailure.audioTooLong.isFallbackEligible)
        #expect(!CaptureFailure.noSpeech.isFallbackEligible)
        #expect(!CaptureFailure.notAuthorized.isFallbackEligible)
    }
}
