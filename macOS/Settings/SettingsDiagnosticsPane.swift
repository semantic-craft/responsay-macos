import SwiftUI

struct SettingsDiagnosticsPane: View {
    @Environment(AppearanceStore.self) private var appearanceStore

    @Binding var debugLog: Bool
    @Binding var keepRawRecording: Bool
    @Binding var maxRawRecordings: Int
    let exportErrorLog: () -> Void
    let exportDiagnostics: () -> Void

    var body: some View {
        SettingsPaneColumn {
            SettingsPaneHeader(title: "诊断", desc: "调试日志与诊断信息导出。")

                WarmCard {
                    GroupLabel(text: "日志与录音")
                    SettingsToggleRow(title: "调试日志（只记请求路由 / 错误码，不记原文）", desc: nil, binding: $debugLog)
                    SettingsToggleRow(title: "保留原始录音（调试用）", desc: nil, binding: $keepRawRecording)
                    HStack(spacing: 8) {
                        Text("最多保留条数").foregroundStyle(appearanceStore.palette.ink)
                        Spacer(minLength: 8)
                        Text("\(maxRawRecordings)").monospacedDigit().foregroundStyle(appearanceStore.palette.ink2)
                        Stepper("", value: $maxRawRecordings, in: 0...2000, step: 50).labelsHidden()
                    }
                    HStack(spacing: 10) {
                        Button("导出错误日志…") { exportErrorLog() }.controlSize(.small)
                        Button("复制诊断信息") { exportDiagnostics() }.controlSize(.small)
                        Spacer(minLength: 0)
                    }
                    footnote("保留原始录音便于排查识别问题；导出仅含请求路由 / 错误码，不含原文。")
                }
        }
        .navigationTitle("诊断")
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(SettingsTheme.footnote)
            .foregroundStyle(appearanceStore.palette.ink3)
            .fixedSize(horizontal: false, vertical: true)
    }
}
