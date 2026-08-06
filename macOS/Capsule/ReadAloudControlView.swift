import SwiftUI
import ResponsayCore

/// 屏底浮窗朗读控制条:暂停/继续、停止,以及「打开阅读器」。绑定 `ReadAloudDocumentReader`
/// (@Observable),复用 `CapsuleSystemTheme`(暖纸 + 酒红,skin 无关),与录音胶囊视觉一致。
/// 朗读选中文本快捷键 / 划词「朗读」时由 `ReadAloudControlPanel` 在屏底居中弹出。
///
/// The capsule is the remote, not the reader: it can pause, stop, and summon the window, but
/// rate and voice live in the window. It is a click-through non-activating panel, so anything
/// needing keyboard focus (⌘V above all) has to happen over there.
struct ReadAloudControlView: View {
    let reader: ReadAloudDocumentReader
    /// Opens the reader window. Held by the panel's owner, which owns the window controller.
    var onOpenReader: () -> Void

    /// 朗读 follows the app skin, independent of the recording-capsule appearance axis.
    private var tokens: CapsuleTokens { CapsuleTokens.followingSkin() }

    /// Set when 朗读 fell back to a non-selected provider (e.g. 火山 key 失效 → 本机 Kokoro).
    private var notice: String? { reader.errorMessage ?? reader.voiceNotice }
    private var isError: Bool { reader.errorMessage != nil }

    private var statusText: String {
        if let notice { return notice }
        switch reader.phase {
        case .preparing: return "准备朗读…"
        case .playing: return "朗读中"
        case .paused: return "已暂停"
        case .idle: return "朗读结束"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "speaker.wave.2.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isError ? tokens.err : tokens.accentText)
            Text(statusText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isError ? tokens.err : tokens.ink)
                .fixedSize()
                .help(notice ?? statusText)
            controlButton(
                systemName: reader.phase == .playing ? "pause.fill" : "play.fill",
                label: reader.phase == .playing ? "暂停朗读" : "继续朗读",
                disabled: reader.phase == .preparing,
                action: { reader.pauseOrResume() })
            controlButton(
                systemName: "stop.fill", label: "停止朗读", disabled: false,
                action: { reader.stop() })
            controlButton(
                systemName: "arrow.up.left.and.arrow.down.right",
                label: "打开阅读器窗口", disabled: false, prominent: false,
                action: onOpenReader)
        }
        .padding(.horizontal, 14)
        .frame(height: CapsuleSystemTheme.pillHeight + 8)
        .background(.ultraThinMaterial, in: Capsule())
        .background(tokens.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(tokens.line, lineWidth: 1))
        .shadow(color: tokens.shadow,
                radius: CapsuleSystemTheme.shadowRadius, y: CapsuleSystemTheme.shadowY)
        .padding(16)   // transparent shadow padding inside the panel
    }

    private func controlButton(
        systemName: String,
        label: String,
        disabled: Bool,
        prominent: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(prominent ? tokens.accentInk : tokens.ink)
                .frame(width: 28, height: 28)
                .background {
                    if prominent {
                        Circle().fill(tokens.accent)
                    } else {
                        Circle().strokeBorder(tokens.line, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .accessibilityLabel(label)
    }
}
