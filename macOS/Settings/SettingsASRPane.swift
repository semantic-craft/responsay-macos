import SwiftUI
import ResponsayCore

struct SettingsASRPane: View {
    @Environment(AppearanceStore.self) private var appearanceStore
    @AppStorage("byok.asr.model")
    private var selectedASRModel = QwenASRFlashRouting.defaultModel

    @Binding var asrEngineRaw: String
    @Binding var localeRaw: String
    @Binding var showEngineCompare: Bool
    let modelManagers: [LocalModelDownloadManager]
    let residency: LocalEngineResidency
    @Binding var residencyError: String?
    let openDictionary: () -> Void
    let ensureModelManagers: () -> Void
    let refreshModelManagerStatus: () async -> Void

    var body: some View {
        SettingsPaneColumn {
            SettingsPaneHeader(title: "语音识别连接配置", desc: "为语音识别引擎配置密钥、端点、模型与离线模型。")

            SettingsStatusBar {
                StatusDot(state: .green)
                Text("当前语音识别在「设置 · 模型」选择")
                Spacer(minLength: 0)
                Text("这里只配置密钥、端点和模型 ID").foregroundStyle(appearanceStore.palette.ink3)
            }
            .onAppear {
                    let normalized = ASREngine.selected.rawValue
                    if asrEngineRaw != normalized { asrEngineRaw = normalized }
                }
                HStack {
                    Button("各引擎对比…") { showEngineCompare = true }
                        .controlSize(.small)
                        .popover(isPresented: $showEngineCompare) { engineComparison }
                    Spacer()
                }
                .padding(.horizontal, 4)
                CapabilityCardView(capability: .asr, preferredProviderId: currentCloudProviderId)
                    .id("asr-config-\(currentCloudProviderId ?? "cloud")")
                WarmCard {
                    LabeledRow(label: "默认听写语言") {
                        Picker("", selection: $localeRaw) {
                            if currentCloudProviderId == QwenASRFlashRouting.providerId {
                                Text("自动检测").tag(CaptureLocale.automatic.rawValue)
                            }
                            Text("English").tag(CaptureLocale.english.rawValue)
                            Text("中文").tag(CaptureLocale.chinese.rawValue)
                            if supportsMixedLanguageHints {
                                Text("中英混合").tag(CaptureLocale.mixed.rawValue)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 160)
                    }
                }
                // Apple 系统原生 leads the local options: zero-download, always
                // available. Named to match the downloadable offline models below.
                if let apple = ASREngine.apple.offlineModelInfo {
                    WarmCard {
                        CapabilityHeader(
                            systemImage: "apple.logo",
                            title: "Apple 系统原生",
                            subtitle: "\(apple.summary)")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("系统自带 · 零下载，断网可用")
                                .font(.system(size: 12))
                                .foregroundStyle(appearanceStore.palette.ink3)
                            Text("出品方：\(apple.vendor)")
                                .font(.system(size: 12))
                                .foregroundStyle(appearanceStore.palette.ink3)
                            ForEach(apple.highlights, id: \.self) { highlight in
                                Text("· 厂商称：\(highlight)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(appearanceStore.palette.ink3)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                // 离线标点模型 leads the offline section: it's what gives the offline 如实
                // 听写 its punctuation (the other offline engines emit none). On-device, no LLM.
                SettingsLocalModelCard(
                    capability: .punctuation,
                    title: "离线标点（如实听写加标点）",
                    subtitle: "离线「如实」听写本身不带标点；装上它就在本机给中英文补标点，零联网、零 LLM。下载即用，下方各离线识别模型都会用到它。",
                    modelManagers: modelManagers,
                    residency: residency,
                    residencyError: $residencyError)
                SettingsLocalModelCard(
                    capability: .asr,
                    title: "本地语音识别选择",
                    subtitle: "纯原生支持、断网可用。一般占用空间越大、效果越好，可自行比对；这几个离线模型目前尚未经过充分测试，仅为可用级别。如需更改模型下载位置，请前往左侧「离线模型下载与管理」。",
                    modelManagers: modelManagers,
                    residency: residency,
                    residencyError: $residencyError)
                HStack(spacing: 6) {
                    Image(systemName: "text.book.closed")
                        .font(SettingsTheme.footnote)
                        .foregroundStyle(appearanceStore.palette.ink3)
                    Text("专名、术语、案号的热词纠偏在")
                        .font(SettingsTheme.footnote)
                        .foregroundStyle(appearanceStore.palette.ink3)
                    Button("识别词典") { openDictionary() }
                        .buttonStyle(.plain)
                        .font(SettingsTheme.footnote.weight(.semibold))
                        .foregroundStyle(appearanceStore.palette.accent)
                    Text("中维护，对所有支持的引擎生效。")
                        .font(SettingsTheme.footnote)
                        .foregroundStyle(appearanceStore.palette.ink3)
                }
                .padding(.horizontal, 4)
        }
        .navigationTitle("语音识别连接配置")
        .onAppear {
            normalizeProviderSpecificLocale()
            Task { await refreshModelManagerStatus() }
            ensureModelManagers()
        }
        .onChange(of: currentCloudProviderId) { _, _ in
            normalizeProviderSpecificLocale()
        }
        .onChange(of: selectedASRModel) { _, _ in
            normalizeProviderSpecificLocale()
        }
    }

    private var currentCloudProviderId: String? {
        ASREngine(rawValue: asrEngineRaw)?.associatedProviderId
    }

    private var supportsMixedLanguageHints: Bool {
        currentCloudProviderId == QwenASRFlashRouting.providerId
            && QwenASRHotwords.languageHints(for: .mixed, model: selectedASRModel).count > 1
    }

    private func normalizeProviderSpecificLocale() {
        if localeRaw == CaptureLocale.mixed.rawValue, !supportsMixedLanguageHints {
            localeRaw = CaptureLocale.chinese.rawValue
        } else if localeRaw == CaptureLocale.automatic.rawValue,
                  currentCloudProviderId != QwenASRFlashRouting.providerId {
            localeRaw = Locale.current.identifier.lowercased().hasPrefix("en")
                ? CaptureLocale.english.rawValue
                : CaptureLocale.chinese.rawValue
        }
    }

    private var engineComparison: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("各引擎对比").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("").gridColumnAlignment(.leading)
                    Text("延迟"); Text("准确"); Text("隐私"); Text("联网")
                }
                .foregroundStyle(.secondary)
                engineCompareRow("整段识别", "松手后~1s", "好", "云端", "需要")
                engineCompareRow("本机离线", "稍慢", "一般", "最高·离线", "不需")
            }
            .font(.caption)
            Text("识别始终使用你在上方选定的引擎，不同场景不会自动切换。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 380)
    }

    private func engineCompareRow(
        _ name: String, _ latency: String, _ accuracy: String, _ privacy: String, _ network: String
    ) -> some View {
        GridRow {
            Text(name).fontWeight(.medium)
            Text(latency); Text(accuracy); Text(privacy); Text(network)
        }
    }
}
