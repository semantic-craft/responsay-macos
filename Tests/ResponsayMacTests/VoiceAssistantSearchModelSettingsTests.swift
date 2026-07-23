import ResponsayCore
import XCTest
@testable import ResponsayMac

/// 联网搜索专属模型(任意提问)的选择 + 候选解析 + 路由。纯 UserDefaults / catalog 逻辑用注入的
/// `defaults`;`resolveSearch` 用注入了 `keyReader` 的 dispatcher,不碰真钥匙串。
@MainActor
final class VoiceAssistantSearchModelSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "test.va.searchmodel"

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

    // MARK: - preferredProviderId

    func testPreferredDefaultsToAuto() {
        XCTAssertNil(VoiceAssistantSearchModelSettings.preferredProviderId(defaults: defaults))
    }

    func testPreferredValidProvider() {
        defaults.set("zhipu", forKey: VoiceAssistantSearchModelSettings.key)
        XCTAssertEqual(VoiceAssistantSearchModelSettings.preferredProviderId(defaults: defaults), "zhipu")
    }

    func testPreferredNonSearchProviderFallsBackToAuto() {
        defaults.set("deepseek", forKey: VoiceAssistantSearchModelSettings.key)  // 不可联网
        XCTAssertNil(VoiceAssistantSearchModelSettings.preferredProviderId(defaults: defaults))
    }

    // MARK: - orderedCandidates

    func testAutoCandidatesAreDefaultOrder() {
        XCTAssertEqual(VoiceAssistantSearchModelSettings.orderedCandidates(defaults: defaults),
                       ["qwen", "zhipu", "mimo", "doubao", "openai"])
    }

    func testPreferredCandidateFirstThenRest() {
        defaults.set("mimo", forKey: VoiceAssistantSearchModelSettings.key)
        XCTAssertEqual(VoiceAssistantSearchModelSettings.orderedCandidates(defaults: defaults),
                       ["mimo", "qwen", "zhipu", "doubao", "openai"])
    }

    // MARK: - displayName

    func testDisplayNames() {
        XCTAssertEqual(VoiceAssistantSearchModelSettings.displayName(for: "qwen"), "阿里云百炼")
        XCTAssertEqual(VoiceAssistantSearchModelSettings.displayName(for: "zhipu"), "智谱GLM")
        XCTAssertEqual(VoiceAssistantSearchModelSettings.displayName(for: "mimo"), "小米Mimo")
    }

    // MARK: - resolveSearch routing

    private func dispatcher(hasKey: Bool) -> ProviderConfigDispatcher {
        ProviderConfigDispatcher(defaults: defaults, keyReader: { _ in hasKey ? "sk-test" : nil })
    }

    func testResolveSearchAutoPrefersActiveQwenWhenKeyed() {
        // 自动 + 默认主模型(qwen, 可联网) → 用 qwen。
        let ep = LLMEndpointResolver.resolveSearch(defaults: defaults, dispatcher: dispatcher(hasKey: true))
        XCTAssertEqual(ep?.providerId, "qwen")
    }

    func testResolveSearchExplicitProviderWins() {
        defaults.set("mimo", forKey: VoiceAssistantSearchModelSettings.key)
        let ep = LLMEndpointResolver.resolveSearch(defaults: defaults, dispatcher: dispatcher(hasKey: true))
        XCTAssertEqual(ep?.providerId, "mimo")
    }

    func testResolveSearchNilWhenNoSearchModelHasKey() {
        let ep = LLMEndpointResolver.resolveSearch(defaults: defaults, dispatcher: dispatcher(hasKey: false))
        XCTAssertNil(ep)
    }

    // MARK: - capsuleSource (设计稿 Variant B 署名)

    func testCapsuleSourceMapping() {
        XCTAssertEqual(VoiceAssistantSearchModelSettings.capsuleSource(for: "qwen"),
                       CapsuleSearchSource(monogram: "通", name: "通义千问"))
        XCTAssertEqual(VoiceAssistantSearchModelSettings.capsuleSource(for: "zhipu"),
                       CapsuleSearchSource(monogram: "智", name: "智谱"))
        XCTAssertEqual(VoiceAssistantSearchModelSettings.capsuleSource(for: "mimo"),
                       CapsuleSearchSource(monogram: "Mi", name: "MiMo"))
        XCTAssertEqual(VoiceAssistantSearchModelSettings.capsuleSource(for: "doubao"),
                       CapsuleSearchSource(monogram: "豆", name: "豆包"))
        XCTAssertNil(VoiceAssistantSearchModelSettings.capsuleSource(for: "deepseek"))
    }
}
