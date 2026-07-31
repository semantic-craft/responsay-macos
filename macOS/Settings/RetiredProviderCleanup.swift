import Foundation

/// One-time removal of a retired provider's persisted selection and secrets (智谱 GLM, 退役于
/// 本次改动)。没有这一步，卸掉 provider 后用户机器上仍留着已存的模型选择和钥匙串密钥：选择会让
/// dispatcher 回退到默认 provider（用户看不出原因），密钥则是无人再用的长期驻留凭据。
///
/// 幂等：完成标记最后写入，中途失败（例如钥匙串被锁）下次启动会重试。
enum RetiredProviderCleanup {
    static let markerKey = "providerCleanup.zhipu.v1"

    private static let providerId = "zhipu"
    private static let configSuffixes = ["region", "plan", "model", "voice", "baseURL"]
    private static let credentialAccounts = [
        "byok.zhipu",
        "byok.zhipu.appId",
        "byok.zhipu.accessToken",
    ]

    static func run(
        defaults: UserDefaults = .standard,
        deleteCredential: (String) -> Bool = { BYOKKeychain.delete($0) }
    ) {
        guard !defaults.bool(forKey: markerKey) else { return }

        // 仅当「当前选中的就是退役 provider」才清 active 键：否则会把用户正在用的其它 provider
        // 的配置一起抹掉。
        let activeProviderKey = CapabilityProviderConfigStore.activeKey("provider", capability: .llm)
        if defaults.string(forKey: activeProviderKey) == providerId {
            defaults.removeObject(forKey: activeProviderKey)
            for suffix in configSuffixes {
                defaults.removeObject(
                    forKey: CapabilityProviderConfigStore.activeKey(suffix, capability: .llm))
            }
        }

        // per-provider 作用域的值无条件清理——它们只属于这个 provider。
        for suffix in configSuffixes {
            defaults.removeObject(
                forKey: CapabilityProviderConfigStore.scopedKey(
                    suffix, providerId: providerId, capability: .llm))
        }
        if defaults.string(forKey: VoiceAssistantSearchModelSettings.key) == providerId {
            defaults.removeObject(forKey: VoiceAssistantSearchModelSettings.key)
        }
        defaults.removeObject(forKey: "byok.\(providerId).boostingTableId")

        var deletedAllCredentials = true
        for account in credentialAccounts where !deleteCredential(account) {
            deletedAllCredentials = false
        }
        // 钥匙串没清干净就不落标记，下次启动再试；UserDefaults 侧的清理是幂等的。
        guard deletedAllCredentials else { return }
        defaults.set(true, forKey: markerKey)
    }
}
