import Testing
@testable import ResponsayCore

// MARK: - 254 · Provider setup prompt condition

@Test func shouldShow_whenLLMNotConfiguredAndNotDismissed_returnsTrue() {
    let summary = ProviderStatusSummary(asr: .ready, llm: .notConfigured, tts: .ready)
    #expect(ProviderSetupPromptCondition.shouldShow(summary: summary, dismissedThisSession: false))
}

@Test func shouldShow_whenLLMReady_returnsFalse() {
    let summary = ProviderStatusSummary(asr: .ready, llm: .ready, tts: .ready)
    #expect(!ProviderSetupPromptCondition.shouldShow(summary: summary, dismissedThisSession: false))
}

@Test func shouldShow_whenDismissedThisSession_returnsFalse() {
    let summary = ProviderStatusSummary(asr: .ready, llm: .notConfigured, tts: .ready)
    #expect(!ProviderSetupPromptCondition.shouldShow(summary: summary, dismissedThisSession: true))
}

@Test func shouldShow_whenLLMErrorOrUnknown_returnsFalse() {
    let errorSummary = ProviderStatusSummary(asr: .ready, llm: .error, tts: .ready)
    let unknownSummary = ProviderStatusSummary(asr: .ready, llm: .unknown, tts: .ready)
    #expect(!ProviderSetupPromptCondition.shouldShow(summary: errorSummary, dismissedThisSession: false))
    #expect(!ProviderSetupPromptCondition.shouldShow(summary: unknownSummary, dismissedThisSession: false))
}
