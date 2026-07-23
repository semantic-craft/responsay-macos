public enum ProviderSetupPromptCondition {
    public static func shouldShow(summary: ProviderStatusSummary, dismissedThisSession: Bool) -> Bool {
        summary.llm == .notConfigured && !dismissedThisSession
    }
}
