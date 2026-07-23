import SwiftUI

struct SettingsTTSPane: View {
    @Environment(AppearanceStore.self) private var appearanceStore

    @Binding var ttsEngineRaw: String
    /// 383 — moved here from the dissolved 英语练习 pane; the only setting that pane
    /// uniquely owned. Drives 范读 / 跟读 speed; shared key with the read-aloud path.
    @Binding var practiceSpeed: String
    let modelManagers: [LocalModelDownloadManager]
    let residency: LocalEngineResidency
    @Binding var residencyError: String?
    let ensureModelManagers: () -> Void

    var body: some View {
        SettingsPaneColumn {
            SettingsPaneHeader(title: "文本朗读连接配置", desc: "配置朗读引擎的密钥、端点、模型与音色，以及默认朗读语速。")

            SettingsStatusBar {
                StatusDot(state: .gray)
                Text("当前朗读引擎在「设置 · 模型」选择")
                Spacer(minLength: 0)
                Text("这里只配置密钥、端点、模型 ID 和音色").foregroundStyle(appearanceStore.palette.ink3)
            }
            CapabilityCardView(capability: .tts, preferredProviderId: currentCloudProviderId)
                .id("tts-config-\(currentCloudProviderId ?? "cloud")")
            SettingsLocalModelCard(
                capability: .tts,
                title: "轻量内置模型（开箱即用）",
                subtitle: "App 原生支持，一键下载，断网可用",
                modelManagers: modelManagers,
                residency: residency,
                residencyError: $residencyError)
            WarmCard {
                GroupLabel(text: "朗读 & 跟读")
                LabeledRow(label: "默认朗读语速") {
                    Picker("", selection: $practiceSpeed) {
                        Text("0.75×").tag("0.75")
                        Text("0.9×").tag("0.9")
                        Text("1.0×").tag("1.0")
                        Text("1.1×").tag("1.1")
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 260)
                }
                Text("「朗读」由「朗读选中文本」快捷键 / 菜单或地道外文卡片上的 🔊 触发；「跟读」是放慢语速跟着范读练习。范读音色取自上面选择的朗读引擎，放慢语速有助于捕捉连读与重音。")
                    .font(SettingsTheme.footnote).foregroundStyle(appearanceStore.palette.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .navigationTitle("文本朗读连接配置")
        .onAppear { ensureModelManagers() }
    }

    private var currentCloudProviderId: String? {
        TTSEngine(rawValue: ttsEngineRaw)?.providerID
    }
}
