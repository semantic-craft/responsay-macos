import SwiftUI

struct SettingsDataPane: View {
    @Environment(AppearanceStore.self) private var appearanceStore

    @AppStorage(PersistentASRContextSettings.enabledKey)
    private var persistentASRContextEnabled = false
    @State private var showClearPersistentContextConfirmation = false
    @State private var showPersistentContextStorageFailure = false

    @Binding var keepHistory: Bool
    @Binding var historyCleanup: String

    var body: some View {
        SettingsPaneColumn {
            SettingsPaneHeader(title: "数据", desc: "听写历史只存在本机，可随时清理。")

            WarmCard {
                CardHeader(systemImage: "tray.full", title: "听写历史",
                           subtitle: "仅保存在本机数据库中。", accent: SettingsTheme.cSys)
                WarmDivider()
                SettingsToggleRow(title: "保留听写历史", desc: nil, binding: $keepHistory)
                LabeledRow(label: "自动清理") {
                    Picker("", selection: $historyCleanup) {
                        Text("不清理").tag("never")
                        Text("7 天").tag("7")
                        Text("30 天").tag("30")
                        Text("90 天").tag("90")
                    }
                    .labelsHidden().frame(maxWidth: 160)
                }
                Text("听写历史和学习日志按此期限清理；自动学到的词条会继续保留在识别词典中。")
                    .font(SettingsTheme.footnote).foregroundStyle(appearanceStore.palette.ink3)
            }
            WarmCard {
                CardHeader(
                    systemImage: "text.bubble",
                    title: "千问识别上下文",
                    subtitle: "让千问实时识别在重启后继续参考最近原始识别结果。",
                    accent: SettingsTheme.cSys)
                WarmDivider()
                SettingsToggleRow(
                    title: "跨重启保留最近上下文",
                    desc: "默认关闭。开启后仅在本机按目标 App 的 Bundle ID 隔离保存；每个 App 最多 5 条，2 小时后自动删除。",
                    binding: persistentContextBinding)
                WarmDivider()
                HStack(alignment: .top) {
                    Text("只保存千问 ASR 返回的原始最终文本，不保存录音、识别中间结果、改写文本、助手消息或完整听写历史。")
                        .font(SettingsTheme.footnote)
                        .foregroundStyle(appearanceStore.palette.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 12)
                    Button("清除已保存上下文…", role: .destructive) {
                        showClearPersistentContextConfirmation = true
                    }
                }
                Text("关闭开关或单独清除只会删除这份上下文，不影响识别词典、已学习别名或撤销记录。")
                    .font(SettingsTheme.footnote)
                    .foregroundStyle(appearanceStore.palette.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            WarmCard {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("清除全部数据…").foregroundStyle(appearanceStore.palette.ink)
                        Text("删除历史、缓存与本地索引（不含已下载模型）。")
                            .font(SettingsTheme.footnote).foregroundStyle(appearanceStore.palette.ink3)
                    }
                    Spacer(minLength: 8)
                    HStack(spacing: 10) {
                        SoonChip()
                        Button("清除全部数据…", role: .destructive) {}.disabled(true)
                    }
                }
                Text("导出历史请在主窗口「历史」页操作。")
                    .font(SettingsTheme.footnote).foregroundStyle(appearanceStore.palette.ink3)
            }
        }
        .navigationTitle("数据")
        .onChange(of: historyCleanup) { _, _ in
            _ = CaptureHistoryStoreFactory.make()
            HistoryRetentionCleanup.pruneLearningRecords()
        }
        .confirmationDialog(
            "清除已保存的千问识别上下文？",
            isPresented: $showClearPersistentContextConfirmation,
            titleVisibility: .visible
        ) {
            Button("清除上下文", role: .destructive) {
                if !PersistentASRContextSettings.clear() {
                    showPersistentContextStorageFailure = true
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只删除跨重启保存的 Context；当前会话内存和识别词典不会被删除。")
        }
        .alert("无法更新千问识别上下文", isPresented: $showPersistentContextStorageFailure) {
            Button("好", role: .cancel) {}
        } message: {
            Text("本地存储操作失败。为保护隐私，跨重启上下文将保持关闭或维持原状态；请稍后重试。")
        }
    }

    private var persistentContextBinding: Binding<Bool> {
        Binding(
            get: { persistentASRContextEnabled },
            set: { enabled in
                if !PersistentASRContextSettings.setEnabled(enabled) {
                    showPersistentContextStorageFailure = true
                }
                persistentASRContextEnabled = PersistentASRContextSettings.isEnabled()
            })
    }
}
