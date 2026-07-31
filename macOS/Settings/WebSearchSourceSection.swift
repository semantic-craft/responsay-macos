import SwiftUI
import ResponsayCore

/// 设置 ·「任意提问 → 联网搜索」打开后的搜索来源配置。
///
/// 两条路二选一：
/// - **跟随模型自带联网**（默认，原行为）：把这一问路由到一个可联网的模型，模型自己搜自己答。
/// - **独立检索服务**（豆包搜索 / Perplexity）：App 先检索，再把结果交给当前文本模型作答，
///   主模型不支持联网也能用，来源也变成检索服务返回的结构化字段。
///
/// 拆成独立 View 是为了让 `SettingsRewritePane` 不因为这一块继续膨胀；密钥读写都走钥匙串。
struct WebSearchSourceSection: View {
    @Environment(AppearanceStore.self) private var appearanceStore

    /// "" = 跟随模型自带联网；其余 = `WebSearchBackendKind.rawValue`。
    @AppStorage(WebSearchProviderSettings.key) private var searchBackend = ""
    /// 联网搜索专属模型（仅「跟随模型自带联网」这一档有意义）。"" = 自动。
    @AppStorage(VoiceAssistantSearchModelSettings.key) private var searchProvider = ""

    @State private var searchKey = ""
    @State private var probeStatus = ""
    @State private var probing = false

    private var selectedKind: WebSearchBackendKind? {
        WebSearchBackendKind(rawValue: searchBackend)
    }

    var body: some View {
        // 与 WarmCard 自身的 VStack 同一节奏，嵌一层不改变视觉行距。
        VStack(alignment: .leading, spacing: 20) {
            LabeledRow(label: "搜索来源") {
                Picker("", selection: $searchBackend) {
                    Text("跟随模型自带联网").tag("")
                    ForEach(WebSearchBackendKind.allCases, id: \.rawValue) { kind in
                        Text(kind.displayName).tag(kind.rawValue)
                    }
                }
                .pickerStyle(.menu).labelsHidden().frame(width: 220)
            }

            if let kind = selectedKind {
                backendRows(kind)
            } else {
                modelRows
            }
        }
        .onAppear { reload() }
        .onChange(of: searchBackend) { _, _ in reload() }
        .onChange(of: searchKey) { _, _ in writeKey() }
    }

    // MARK: - 独立检索服务

    @ViewBuilder private func backendRows(_ kind: WebSearchBackendKind) -> some View {
        LabeledRow(label: "API Key") {
            SecureKeyField(placeholder: "粘贴 \(kind.displayName) 的 API Key", text: $searchKey)
        }
        HStack(spacing: 8) {
            Button("测试连接") { probe(kind) }
                .controlSize(.small)
                .disabled(probing || searchKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if !probeStatus.isEmpty {
                Text(probeStatus)
                    .font(SettingsTheme.footnote).foregroundStyle(appearanceStore.palette.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        footnote(hint(for: kind))
        footnote("选了检索服务后，这一问会先由它联网检索，再把检索到的网页交给你当前的文本模型作答——主模型不支持联网也能用，答案里还会带上来源序号。代价是比模型自带联网多一次往返，慢一点。密钥存系统钥匙串。")
    }

    private func hint(for kind: WebSearchBackendKind) -> String {
        switch kind {
        case .doubao:
            return "豆包搜索 Global 版：在火山引擎「联网搜索控制台 → API Key 管理 → 按量后付费」创建，注意不是方舟（豆包大模型）的那把 Key。仅支持按量后付费；每个火山账号每月 500 次免费额度；账号默认 5 QPS。"
        case .perplexity:
            return "Perplexity：在 Perplexity 的 API 设置页创建密钥。走的是 /search 纯检索接口，不是 sonar 作答模型。"
        }
    }

    // MARK: - 跟随模型自带联网

    @ViewBuilder private var modelRows: some View {
        LabeledRow(label: "联网模型") {
            Picker("", selection: $searchProvider) {
                Text("自动").tag("")
                ForEach(VoiceAssistantSearchModelSettings.searchProviders, id: \.self) { id in
                    Text(VoiceAssistantSearchModelSettings.displayName(for: id)).tag(id)
                }
            }
            .pickerStyle(.menu).labelsHidden().frame(width: 220)
        }
        footnote("「自动」= 优先用你当前的文本模型（若它本就支持联网），否则用第一个你已配好密钥的联网模型。这几家都没配密钥时会自动退回普通问答——去「模型与密钥」给对应模型填好密钥，或在上面改选一个独立检索服务。")
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(SettingsTheme.footnote).foregroundStyle(appearanceStore.palette.ink3)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - 密钥读写

    private func reload() {
        probeStatus = ""
        searchKey = selectedKind.map { WebSearchProviderSettings.apiKey(for: $0) } ?? ""
    }

    /// 写回当前选中服务的那一格。切换服务时 `reload()` 先把 searchKey 换成新服务的密钥，
    /// 再触发这里——所以永远不会把一家的 Key 写进另一家的格子。
    private func writeKey() {
        guard let kind = selectedKind else { return }
        BYOKKeychain.write(searchKey, account: CapabilityCredentialAccount.searchKeyAccount(for: kind))
        probeStatus = ""
    }

    private func probe(_ kind: WebSearchBackendKind) {
        probing = true
        probeStatus = "测试中…"
        let key = searchKey
        Task {
            let result = await WebSearchProviderSettings.probe(kind: kind, apiKey: key)
            probeStatus = result
            probing = false
        }
    }
}
