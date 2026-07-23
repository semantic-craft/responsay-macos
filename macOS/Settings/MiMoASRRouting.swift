import Foundation
import ResponsayCore

enum MiMoASRRouting {
    static let tokenPlanChinaBaseURL = "https://token-plan-cn.xiaomimimo.com/v1"
    static let payAsYouGoBaseURL = "https://api.xiaomimimo.com/v1"

    // MiMo ASR/LLM/TTS now expose 按量付费 and Token Plan as selectable plans, so these are
    // plain pass-throughs — the user's plan / Base URL pick is honored as-is (no more forcing
    // ASR onto Token Plan). They stay as named seams because the dispatcher, the ASR client
    // factory and the settings card all route MiMo through them.

    static func normalizedPlan(
        providerId: String,
        capability: ModelCapability,
        stored: BillingPlan?,
        fallback: BillingPlan
    ) -> BillingPlan {
        stored ?? fallback
    }

    static func normalizedBaseURL(
        providerId: String,
        capability: ModelCapability,
        stored: String?,
        fallback: String
    ) -> String {
        nonEmpty(stored) ?? fallback
    }

    static func normalizedPlanRaw(
        providerId: String,
        capability: ModelCapability,
        storedRaw: String?,
        fallbackRaw: String
    ) -> String {
        normalizedPlan(
            providerId: providerId,
            capability: capability,
            stored: BillingPlan(rawValue: storedRaw ?? ""),
            fallback: BillingPlan(rawValue: fallbackRaw) ?? .payg
        ).rawValue
    }

    static func shouldPersistNormalizedDefaults(providerId: String, capability: ModelCapability) -> Bool {
        false
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
