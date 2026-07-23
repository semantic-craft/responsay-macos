import Foundation
import ResponsayCore

enum CapabilityCredentialAccount {
    /// Keychain account for a provider's API key. 按量付费 (sk-) and Token Plan (tp-) are
    /// different credentials, so a provider that offers more than one billing plan stores
    /// **one key per plan** (`…payg` / `…package`) — switching the 接入点 dropdown then loads
    /// the matching key instead of overwriting the other. Single-plan providers keep the
    /// plain account so existing keys are untouched. Pass `plan` at every read/write site.
    static func apiKeyAccount(
        providerId: String,
        capability: ModelCapability,
        plan: BillingPlan? = nil
    ) -> String {
        let base = capability == .tts
            ? TTSCredential.keychainAccount(for: providerId)
            : TTSCredential.coachAccount(for: providerId)
        guard let plan, ProviderCatalog.providerHasMultipleBillingPlans(providerId, capability: capability) else {
            return base
        }
        return "\(base).\(plan.rawValue)"
    }

    static func appIdAccount(providerId: String) -> String {
        "byok.\(providerId).appId"
    }

    static func accessTokenAccount(providerId: String) -> String {
        "byok.\(providerId).accessToken"
    }
}
