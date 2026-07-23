import Foundation
import Testing
@testable import ResponsayCore

/// #559 — safe-unavailable reasons must be distinguishable so the capsule can tell the user
/// *why* nothing was inserted (no key vs bad response vs unreachable vs …), and the mapping
/// must never read a provider message string (content-free classification).
struct IntentUnavailableReasonClassificationTests {
    @Test func cancellationClassifiesAsCancelled() {
        #expect(IntentUnavailableReason.classify(compilerError: CancellationError()) == .cancelled)
    }

    @Test func typedCompilerFailurePassesItsReasonThrough() {
        for reason in [IntentUnavailableReason.capabilityUnsupported, .providerTimeout, .compilerUnavailable] {
            #expect(IntentUnavailableReason.classify(compilerError: IntentCompilerFailure(reason)) == reason)
        }
    }

    @Test func missingKeyOrConfigIsCompilerUnavailableNotFailed() {
        // 无 Key / 未配置 must read as "not set up", not "provider failed" — the old catch-all
        // collapsed both to compilerFailed and mislabelled a no-key user as a network outage.
        #expect(IntentUnavailableReason.classify(compilerError: LLMError.notConfigured) == .compilerUnavailable)
        #expect(IntentUnavailableReason.classify(compilerError: LLMError.invalidEndpoint("x")) == .compilerUnavailable)
        #expect(IntentUnavailableReason.classify(compilerError: LLMError.invalidConfiguration("x")) == .compilerUnavailable)
    }

    @Test func networkAndHTTPAreProviderUnreachable() {
        #expect(IntentUnavailableReason.classify(compilerError: LLMError.network("timeout")) == .compilerFailed)
        #expect(IntentUnavailableReason.classify(compilerError: LLMError.http(status: 500, body: "")) == .compilerFailed)
    }

    @Test func emptyOrBadJSONIsBadResponse() {
        #expect(IntentUnavailableReason.classify(compilerError: LLMError.emptyContent) == .invalidPlan)
        #expect(IntentUnavailableReason.classify(compilerError: LLMError.badJSON("x")) == .invalidPlan)
    }

    @Test func unknownErrorFallsBackToCompilerFailed() {
        struct Mystery: Error {}
        #expect(IntentUnavailableReason.classify(compilerError: Mystery()) == .compilerFailed)
    }
}
