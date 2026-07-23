import SwiftUI
import ResponsayCore

/// 屏底浮窗朗读控制条:暂停/继续 + 停止。绑定 `ReadAloudController`(@Observable),
/// 复用 `CapsuleSystemTheme`(暖纸 + 酒红,skin 无关),与录音胶囊视觉一致。
/// 划词「朗读」时由 `ReadAloudControlPanel` 在屏底居中弹出。
struct ReadAloudControlView: View {
    let controller: ReadAloudController

    /// 497: set when 朗读 fell back to a non-selected provider (e.g. 火山 key 失效 → 本机 Kokoro).
    private var notice: String? { controller.activeVoiceNotice }

    private var statusText: String {
        if let notice { return notice }
        if controller.isPreparing { return "准备朗读…" }
        return controller.isPlaying ? "朗读中" : "已暂停"
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: notice != nil ? "exclamationmark.triangle.fill" : "speaker.wave.2.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(notice != nil ? CapsuleSystemTheme.err : CapsuleSystemTheme.accentText)
            Text(statusText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(notice != nil ? CapsuleSystemTheme.err : CapsuleSystemTheme.ink)
                .fixedSize()
                .help(notice ?? statusText)
            controlButton(
                systemName: controller.isPlaying ? "pause.fill" : "play.fill",
                disabled: controller.isPreparing,
                action: { controller.pauseOrResume() })
            controlButton(systemName: "stop.fill", disabled: false, action: { controller.stop() })
        }
        .padding(.horizontal, 14)
        .frame(height: CapsuleSystemTheme.pillHeight + 8)
        .background(.ultraThinMaterial, in: Capsule())
        .background(CapsuleSystemTheme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(CapsuleSystemTheme.line, lineWidth: 1))
        .shadow(color: CapsuleSystemTheme.shadow,
                radius: CapsuleSystemTheme.shadowRadius, y: CapsuleSystemTheme.shadowY)
        .padding(16)   // transparent shadow padding inside the panel
    }

    private func controlButton(systemName: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CapsuleSystemTheme.accentInk)
                .frame(width: 28, height: 28)
                .background(Circle().fill(CapsuleSystemTheme.accent))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .accessibilityLabel(systemName == "stop.fill" ? "停止朗读" : "暂停或继续朗读")
    }
}
