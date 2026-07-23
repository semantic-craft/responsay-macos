import SwiftUI

struct SettingsModelControls: View {
    let manager: LocalModelDownloadManager

    var body: some View {
        switch manager.state {
        case .checking:
            ProgressView().controlSize(.small)
        case .notInstalled:
            Button("下载并安装") { manager.download() }
        case .downloading(let fraction):
            HStack(spacing: 8) {
                ProgressView(value: fraction).frame(width: 120)
                Text("\(Int(fraction * 100))%").monospacedDigit().foregroundStyle(.secondary)
                Button("取消") { manager.cancel() }
            }
        case .verifying:
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("校验中…").foregroundStyle(.secondary) }
        case .extracting:
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("部署中…").foregroundStyle(.secondary) }
        case .installed:
            HStack(spacing: 8) {
                Label("已安装", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                if let summary = manager.selfCheckSummary {
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }
                if manager.supportsSelfCheck {
                    Button("自检") { manager.selfCheck() }
                }
                Button("删除", role: .destructive) { manager.delete() }
            }
        case .failed(let message):
            HStack(spacing: 8) {
                Label("失败", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Button("重试") { manager.download() }
            }
            .help(message)
        }
    }
}
