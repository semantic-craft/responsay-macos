import XCTest
import ResponsayCore
@testable import ResponsayMac

/// 智谱退役后的一次性清理：既要抹掉遗留选择与密钥，又不能误伤用户当前在用的其它 provider。
final class RetiredProviderCleanupTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "test.retiredProviderCleanup"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    private func activeKey(_ suffix: String) -> String {
        CapabilityProviderConfigStore.activeKey(suffix, capability: .llm)
    }

    private func scopedKey(_ suffix: String, _ providerId: String) -> String {
        CapabilityProviderConfigStore.scopedKey(suffix, providerId: providerId, capability: .llm)
    }

    func testClearsActiveSelectionWhenRetiredProviderWasSelected() {
        defaults.set("zhipu", forKey: activeKey("provider"))
        defaults.set("glm-5-turbo", forKey: activeKey("model"))
        defaults.set("https://open.bigmodel.cn/api/paas/v4", forKey: activeKey("baseURL"))

        RetiredProviderCleanup.run(defaults: defaults, deleteCredential: { _ in true })

        XCTAssertNil(defaults.string(forKey: activeKey("provider")))
        XCTAssertNil(defaults.string(forKey: activeKey("model")))
        XCTAssertNil(defaults.string(forKey: activeKey("baseURL")))
        XCTAssertTrue(defaults.bool(forKey: RetiredProviderCleanup.markerKey))
    }

    /// 关键边界：用户当前用的是别家（qwen），清理只能动 zhipu 的作用域键，不许碰 active 配置。
    func testKeepsAnotherProvidersActiveConfigIntact() {
        defaults.set("qwen", forKey: activeKey("provider"))
        defaults.set("qwen3.7-flash", forKey: activeKey("model"))
        defaults.set("glm-5-turbo", forKey: scopedKey("model", "zhipu"))

        RetiredProviderCleanup.run(defaults: defaults, deleteCredential: { _ in true })

        XCTAssertEqual(defaults.string(forKey: activeKey("provider")), "qwen")
        XCTAssertEqual(defaults.string(forKey: activeKey("model")), "qwen3.7-flash")
        XCTAssertNil(defaults.string(forKey: scopedKey("model", "zhipu")))
    }

    func testClearsSearchProviderPreferenceOnlyWhenItPointedAtRetiredProvider() {
        defaults.set("zhipu", forKey: VoiceAssistantSearchModelSettings.key)
        RetiredProviderCleanup.run(defaults: defaults, deleteCredential: { _ in true })
        XCTAssertNil(defaults.string(forKey: VoiceAssistantSearchModelSettings.key))

        let other = UserDefaults(suiteName: suite + ".other")!
        other.removePersistentDomain(forName: suite + ".other")
        other.set("mimo", forKey: VoiceAssistantSearchModelSettings.key)
        RetiredProviderCleanup.run(defaults: other, deleteCredential: { _ in true })
        XCTAssertEqual(other.string(forKey: VoiceAssistantSearchModelSettings.key), "mimo")
        other.removePersistentDomain(forName: suite + ".other")
    }

    func testDeletesEveryCredentialAccount() {
        var deleted: [String] = []
        RetiredProviderCleanup.run(defaults: defaults, deleteCredential: { deleted.append($0); return true })
        XCTAssertEqual(deleted.sorted(), ["byok.zhipu", "byok.zhipu.accessToken", "byok.zhipu.appId"])
    }

    /// 钥匙串删除失败（例如被锁）→ 不落标记，下次启动重试；否则密钥会永远留在机器上。
    func testRetriesWhenCredentialDeletionFails() {
        RetiredProviderCleanup.run(defaults: defaults, deleteCredential: { _ in false })
        XCTAssertFalse(defaults.bool(forKey: RetiredProviderCleanup.markerKey))

        var attempts = 0
        RetiredProviderCleanup.run(defaults: defaults, deleteCredential: { _ in attempts += 1; return true })
        XCTAssertEqual(attempts, 3)
        XCTAssertTrue(defaults.bool(forKey: RetiredProviderCleanup.markerKey))
    }

    func testIsIdempotentOnceMarked() {
        defaults.set(true, forKey: RetiredProviderCleanup.markerKey)
        defaults.set("zhipu", forKey: activeKey("provider"))
        var attempts = 0
        RetiredProviderCleanup.run(defaults: defaults, deleteCredential: { _ in attempts += 1; return true })
        XCTAssertEqual(attempts, 0)
        XCTAssertEqual(defaults.string(forKey: activeKey("provider")), "zhipu")   // 标记后不再动
    }
}
