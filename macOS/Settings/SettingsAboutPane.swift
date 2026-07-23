import SwiftUI

struct SettingsAboutPane: View {
    @Environment(AppearanceStore.self) private var appearanceStore
    let updateService: AutoUpdateService

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }

    var body: some View {
        SettingsPaneColumn {
            SettingsPaneHeader(title: "关于", desc: "版本、引擎与更新。")

            WarmCard {
                GroupLabel(text: "关于")
                infoRow("版本", "法言 · Responsay \(appVersion)")   // 中文名 · 英文名 · 版本
                infoRow("引擎", "Qwen · Sherpa · 多家云端")
                infoRow("设计与开发", "张贤伟 · 深圳大学法律人工智能实训实验室")
                SettingsToggleRow(title: "自动检查更新", desc: nil, binding: Binding(
                    get: { updateService.automaticallyChecksForUpdates },
                    set: { updateService.automaticallyChecksForUpdates = $0 }))
                HStack {
                    Button("检查更新") { updateService.checkForUpdates() }
                        .controlSize(.small)
                        .disabled(!updateService.canCheckForUpdates)
                    Spacer(minLength: 0)
                }
                footnote("法言 是一个隐形的 macOS 输入法 / 听写工具：平时不打扰，按热键说话，文字落到光标处。")
            }

            WarmCard {
                GroupLabel(text: "开源鸣谢")
                acknowledgementRow("KeyboardShortcuts", "全局热键绑定 · Sindre Sorhus")
                acknowledgementRow("Sparkle", "macOS 应用自动更新框架")
                acknowledgementRow("sherpa-onnx", "离线语音识别与合成引擎 · k2-fsa")
                acknowledgementRow("ONNX Runtime", "机器学习推理引擎 · Microsoft")
                acknowledgementRow("PaddleOCR", "离线文字识别引擎 · PaddlePaddle")
                acknowledgementRow("Kaze", "录音胶囊窗口与波形动画参考 · fayazara")
                acknowledgementRow("OpenLess", "法律技能面板 UI 设计参考 · appergb")
                acknowledgementRow("orca", "提示音音效素材 · stablyai")
                footnote("感谢以上开源项目及其维护者。")
            }
        }
        .navigationTitle("关于")
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 16) {
            Text(label).foregroundStyle(appearanceStore.palette.ink)
            Spacer(minLength: 8)
            Text(value).foregroundStyle(appearanceStore.palette.ink2)
        }
    }

    private func acknowledgementRow(_ name: String, _ desc: String) -> some View {
        HStack(spacing: 16) {
            Text(name).foregroundStyle(appearanceStore.palette.ink)
            Spacer(minLength: 8)
            Text(desc).foregroundStyle(appearanceStore.palette.ink3).font(SettingsTheme.footnote)
        }
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(SettingsTheme.footnote)
            .foregroundStyle(appearanceStore.palette.ink3)
            .fixedSize(horizontal: false, vertical: true)
    }
}
