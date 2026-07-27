import Testing
import Foundation
@testable import ResponsayCore

/// 记录调用参数的假后端——检索词到底送出去了什么,是这条路唯一容易搞错的地方。
private actor StubSearchBackend: WebSearchBackend {
    nonisolated let kind: WebSearchBackendKind
    private let documents: [WebSearchDocument]
    private(set) var lastQuery = ""
    private(set) var lastLimit = 0

    init(kind: WebSearchBackendKind = .doubao, documents: [WebSearchDocument]) {
        self.kind = kind
        self.documents = documents
    }

    func search(query: String, limit: Int) async throws -> [WebSearchDocument] {
        lastQuery = query
        lastLimit = limit
        return documents
    }
}

private struct FailingSearchBackend: WebSearchBackend {
    let kind: WebSearchBackendKind = .perplexity
    func search(query: String, limit: Int) async throws -> [WebSearchDocument] {
        throw WebSearchError.provider(code: "700901", message: "invalid key")
    }
}

@Suite struct WebSearchRunnerTests {

    private func document(_ title: String, url: String = "https://e.com/a") -> WebSearchDocument {
        WebSearchDocument(title: title, url: url, snippet: "摘要", hostname: "站", publishTime: "2026-06-01")
    }

    @Test func context_wrapsDocumentsInTheFence() async throws {
        let runner = WebSearchRunner(backend: StubSearchBackend(documents: [document("甲")]))
        let block = try #require(await runner.context(for: "问题"))
        #expect(block.contains("[1] 甲"))
        #expect(block.contains(WebSearchContextBuilder.openTag))
    }

    /// 搜到 0 条不是错误:调用方据此退回不带检索的普通作答。
    @Test func context_isNilWhenNothingFound() async throws {
        let runner = WebSearchRunner(backend: StubSearchBackend(documents: []))
        #expect(try await runner.context(for: "问题") == nil)
    }

    /// 检索失败(密钥/额度/网络)要抛出去,由 app 层撤掉「联网搜索」署名——
    /// 不能让用户以为搜过了。
    @Test func context_propagatesBackendFailure() async {
        let runner = WebSearchRunner(backend: FailingSearchBackend())
        await #expect(throws: WebSearchError.self) {
            _ = try await runner.context(for: "问题")
        }
    }

    /// 没有可用主模型(queryAPI == nil)时,超长提问退回截断,而不是原样送去撞接口上限。
    @Test func searchQuery_truncatesWhenNoModelAvailable() async {
        let backend = StubSearchBackend(documents: [])
        let runner = WebSearchRunner(backend: backend)
        _ = try? await runner.documents(for: String(repeating: "字", count: 300))
        let sent = await backend.lastQuery
        #expect(sent.count == WebSearchBackendKind.doubao.queryCharacterLimit)
    }

    @Test func documents_defaultsToFiveResults() async throws {
        let backend = StubSearchBackend(documents: [])
        _ = try await WebSearchRunner(backend: backend).documents(for: "短问题")
        #expect(await backend.lastLimit == WebSearchRunner.defaultResultCount)
        #expect(await backend.lastQuery == "短问题")
    }
}

@Suite struct SearchVerificationBackendTests {

    private func anchor(query: String) -> VerificationAnchor {
        VerificationAnchor(id: "a1", label: query, kind: .caseLaw, query: query)
    }

    /// 检索 API 直接给出标题/URL/摘要,正是 VerifiedSource 要的,不必再绕模型。
    @Test func verify_fillsSourceFromTheMatchingDocument() async throws {
        let backend = StubSearchBackend(documents: [
            WebSearchDocument(
                title: "某某合同纠纷案",
                url: "https://court.example/1234",
                snippet: "(2021)京01民终1234号 判决书"),
        ])
        let source = try await SearchVerificationService.verify(anchor(query: "（2021）京01民终1234号"), using: backend)
        #expect(source?.url == "https://court.example/1234")
        #expect(source?.provider == WebSearchBackendKind.doubao.rawValue)
    }

    /// 对不上的结果绝不回填:锚点保持 pending,而不是被写成「已核验」。
    @Test func verify_returnsNilWhenNothingMatches() async throws {
        let backend = StubSearchBackend(documents: [
            WebSearchDocument(title: "旅游攻略", url: "https://e.com", snippet: "北京周边好去处"),
        ])
        #expect(try await SearchVerificationService.verify(anchor(query: "（2021）京01民终1234号"), using: backend) == nil)
    }
}

@Suite struct VoiceAssistantSearchContextTests {

    /// 检索是按当轮提问做的,追问会重搜——所以检索块挂在**最后**一条 user 消息上,
    /// 而不是像选区那样只挂第一轮。
    @Test func apiMessages_attachesSearchContextToTheLatestUserTurn() {
        let messages = [
            VoiceAssistantMessage(role: "user", content: "第一问"),
            VoiceAssistantMessage(role: "assistant", content: "答"),
            VoiceAssistantMessage(role: "user", content: "追问"),
        ]
        let api = VoiceAssistantViewModel.apiMessages(
            systemPrompt: "sys", messages: messages, selection: nil, searchContext: "<搜索结果>…</搜索结果>")
        #expect(api[1]["content"] == "第一问")
        #expect(api[3]["content"]?.hasPrefix("<搜索结果>…</搜索结果>") == true)
        #expect(api[3]["content"]?.hasSuffix("追问") == true)
    }

    /// 没有检索上下文时,消息数组与接入检索服务之前逐字节一致。
    @Test func apiMessages_unchangedWithoutSearchContext() {
        let messages = [VoiceAssistantMessage(role: "user", content: "hi")]
        let withNil = VoiceAssistantViewModel.apiMessages(
            systemPrompt: "sys", messages: messages, selection: nil, searchContext: nil)
        let legacy = VoiceAssistantViewModel.apiMessages(
            systemPrompt: "sys", messages: messages, selection: nil)
        #expect(withNil == legacy)
    }

    /// 选区 + 检索同时存在:检索材料在前,选区信封与提问在后。
    @Test func apiMessages_searchContextPrecedesSelectionEnvelope() {
        let messages = [VoiceAssistantMessage(role: "user", content: "这段说了什么？")]
        let api = VoiceAssistantViewModel.apiMessages(
            systemPrompt: "sys", messages: messages, selection: "被选中的文字", searchContext: "检索块")
        let content = api[1]["content"] ?? ""
        let searchIndex = try? #require(content.range(of: "检索块")?.lowerBound)
        let selectionIndex = try? #require(content.range(of: "<selected_text>")?.lowerBound)
        #expect(searchIndex != nil && selectionIndex != nil && searchIndex! < selectionIndex!)
    }
}
