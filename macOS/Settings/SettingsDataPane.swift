import SwiftUI

struct SettingsDataPane: View {
    @Environment(AppearanceStore.self) private var appearanceStore

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
    }
}
