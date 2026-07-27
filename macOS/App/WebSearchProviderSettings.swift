import Foundation
import ResponsayCore

/// 联网搜索的**检索服务**选择与密钥，独立于 BYOK 的 LLM 密钥。
///
/// `""`（或任何非法值）= 跟随模型自带联网，行为与接入检索服务之前完全一致
/// （`VoiceAssistantSearchModelSettings` + `LLMSearchControl` / `ArkResponsesSearchRequestBuilder`）。
/// 选了具体服务且填了密钥 = 走「App 先检索、主模型再作答」的两段式（`WebSearchRunner`）。
///
/// 纯 UserDefaults + 可注入的 keyReader，所以能在不碰真钥匙串的前提下单测。
enum WebSearchProviderSettings {
    /// 存的检索服务 id（`WebSearchBackendKind.rawValue`）。
    static let key = "voiceAssistant.searchBackend"

    /// 「测试连接」用的中性检索词——不带用户内容，只验密钥与开通状态。
    static let probeQuery = "人工智能"

    static func selectedKind(defaults: UserDefaults = .standard) -> WebSearchBackendKind? {
        WebSearchBackendKind(rawValue: defaults.string(forKey: key) ?? "")
    }

    static func apiKey(
        for kind: WebSearchBackendKind,
        reader: (String) -> String? = { BYOKKeychain.read($0) }
    ) -> String {
        (reader(CapabilityCredentialAccount.searchKeyAccount(for: kind)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 已选服务 + 已填密钥 → 可用后端；否则 nil（调用方退回模型自带联网）。
    static func backend(
        defaults: UserDefaults = .standard,
        reader: (String) -> String? = { BYOKKeychain.read($0) }
    ) -> (any WebSearchBackend)? {
        guard let kind = selectedKind(defaults: defaults) else { return nil }
        let key = apiKey(for: kind, reader: reader)
        guard !key.isEmpty else { return nil }
        return HTTPWebSearchBackend(kind: kind, apiKey: key)
    }

    /// 「测试连接」：真发一条检索，把条数或服务商的错误码报回给用户。贴完 Key 立刻知道通没通，
    /// 比等到某次提问悄悄退回普通问答强。
    static func probe(kind: WebSearchBackendKind, apiKey: String) async -> String {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return "还没填 API Key" }
        do {
            let documents = try await HTTPWebSearchBackend(kind: kind, apiKey: key)
                .search(query: probeQuery, limit: 3)
            return documents.isEmpty ? "连通，但这次没搜到结果" : "连通 · 返回 \(documents.count) 条"
        } catch {
            return error.localizedDescription
        }
    }
}
