import ResponsayCore
import XCTest
@testable import ResponsayMac

/// 联网搜索的「检索服务」这一档:选了谁、密钥读哪一格、以及它对「模型自带联网」的压制。
/// 纯 UserDefaults + 注入的 keyReader,不碰真钥匙串。
@MainActor
final class WebSearchProviderSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "test.va.searchbackend"

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

    private func select(_ kind: WebSearchBackendKind) {
        defaults.set(kind.rawValue, forKey: WebSearchProviderSettings.key)
    }

    // MARK: - 选择

    func testDefaultsToNoBackend() {
        XCTAssertNil(WebSearchProviderSettings.selectedKind(defaults: defaults))
    }

    func testUnknownStoredValueFallsBackToNoBackend() {
        defaults.set("bing", forKey: WebSearchProviderSettings.key)
        XCTAssertNil(WebSearchProviderSettings.selectedKind(defaults: defaults))
    }

    func testSelectedKinds() {
        select(.doubao)
        XCTAssertEqual(WebSearchProviderSettings.selectedKind(defaults: defaults), .doubao)
        select(.perplexity)
        XCTAssertEqual(WebSearchProviderSettings.selectedKind(defaults: defaults), .perplexity)
    }

    // MARK: - 密钥格

    /// 豆包搜索的 Key 与方舟(豆包大模型)的 Key 是两把,必须落在不同的钥匙串账户上。
    func testSearchKeyAccountIsSeparateFromTheLLMKey() {
        XCTAssertEqual(CapabilityCredentialAccount.searchKeyAccount(for: .doubao), "byok.search.doubao")
        XCTAssertEqual(CapabilityCredentialAccount.searchKeyAccount(for: .perplexity), "byok.search.perplexity")
        XCTAssertNotEqual(
            CapabilityCredentialAccount.searchKeyAccount(for: .doubao),
            CapabilityCredentialAccount.apiKeyAccount(providerId: "doubao", capability: .llm))
    }

    func testApiKeyReadsTheBackendsOwnAccount() {
        let key = WebSearchProviderSettings.apiKey(for: .perplexity) { account in
            account == "byok.search.perplexity" ? "  pplx-abc  " : "wrong-slot"
        }
        XCTAssertEqual(key, "pplx-abc")
    }

    // MARK: - backend 解析

    func testBackendIsNilWithoutSelection() {
        XCTAssertNil(WebSearchProviderSettings.backend(defaults: defaults, reader: { _ in "sk" }))
    }

    /// 选了服务但没填密钥 = 还没配好 → 退回模型自带联网,而不是发一个必然 401 的请求。
    func testBackendIsNilWithoutKey() {
        select(.doubao)
        XCTAssertNil(WebSearchProviderSettings.backend(defaults: defaults, reader: { _ in "" }))
    }

    func testBackendResolvesWhenSelectedAndKeyed() {
        select(.doubao)
        let backend = WebSearchProviderSettings.backend(defaults: defaults, reader: { _ in "sk-test" })
        XCTAssertEqual(backend?.kind, .doubao)
    }

    // MARK: - 与「模型自带联网」互斥

    private var searchCapableEndpoint: LLMEndpoint {
        LLMEndpoint(providerId: "qwen", baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
                    model: "qwen-plus", apiKey: "sk-test")
    }

    func testModelSideSearchStaysOnWithoutABackend() {
        defaults.set(true, forKey: VoiceAssistantWebSearchSettings.key)
        XCTAssertTrue(VoiceAssistantWebSearchSettings.effectiveEnabled(
            endpoint: searchCapableEndpoint, defaults: defaults, keyReader: { _ in "sk-test" }))
    }

    /// 回归:配了检索服务后,重新生成(makeClient)不能再打开模型自带联网——
    /// 否则同一个问题会被搜两遍(检索服务一遍 + 模型一遍)。
    func testBackendSuppressesModelSideSearch() {
        defaults.set(true, forKey: VoiceAssistantWebSearchSettings.key)
        select(.doubao)
        XCTAssertFalse(VoiceAssistantWebSearchSettings.effectiveEnabled(
            endpoint: searchCapableEndpoint, defaults: defaults, keyReader: { _ in "sk-test" }))
    }

    // MARK: - 胶囊署名

    /// 走检索服务时署名的是检索服务本身,不是主模型——搜的是它。
    func testCapsuleSourceCoversSearchBackends() {
        XCTAssertEqual(VoiceAssistantSearchModelSettings.capsuleSource(for: "doubao-search"),
                       CapsuleSearchSource(monogram: "豆", name: "豆包搜索"))
        XCTAssertEqual(VoiceAssistantSearchModelSettings.capsuleSource(for: "perplexity"),
                       CapsuleSearchSource(monogram: "P", name: "Perplexity"))
        // 方舟豆包(LLM)仍然是它自己的署名,没有被检索服务顶掉。
        XCTAssertEqual(VoiceAssistantSearchModelSettings.capsuleSource(for: "doubao"),
                       CapsuleSearchSource(monogram: "豆", name: "豆包"))
    }
}
