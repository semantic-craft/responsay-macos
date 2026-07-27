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

    /// 联网搜索检索服务的 Key。**与同名 LLM provider 的 Key 分开存**——豆包搜索的 Key 由
    /// 联网搜索控制台签发，方舟(豆包 LLM)的 Key 是另一把，共用一格会把请求打到错误的服务上。
    static func searchKeyAccount(for kind: WebSearchBackendKind) -> String {
        switch kind {
        case .doubao:     return "byok.search.doubao"
        case .perplexity: return "byok.search.perplexity"
        }
    }

    static func accessTokenAccount(providerId: String) -> String {
        "byok.\(providerId).accessToken"
    }
}
