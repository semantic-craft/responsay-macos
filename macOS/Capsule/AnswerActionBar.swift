import SwiftUI
import ResponsayCore

/// The 任意提问 answer card's voice-forward action-bar controls (Capsule System design):
/// 🔊 朗读 · 复制 · 重新生成 · ⌥ 追问. Split out of `VoiceAssistantResultPanel` to keep each
/// file small. Internal (not private) only so they can live in their own file.

/// 🔊 朗读 — a wine pill that toggles to a stop affordance while playing.
@MainActor
struct ReadAloudButton: View {
    let isPlaying: Bool
    let isPreparing: Bool
    let enabled: Bool
    let action: () -> Void
    @State private var hovering = false
    private var label: String {
        if isPlaying { return "停止" }
        if isPreparing { return "准备中" }
        return "朗读"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: isPlaying ? "stop.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(MacPalette.accentInk)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(Capsule(style: .continuous).fill(SettingsTheme.wine.opacity(hovering ? 0.92 : 1)))
            .shadow(color: SettingsTheme.wine.opacity(0.45), radius: 5, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .onHover { hovering = $0 }
        .accessibilityLabel(isPlaying ? "停止朗读" : (isPreparing ? "正在准备朗读" : "朗读回答"))
    }
}

/// A 32×32 outline icon button (复制 / 重新生成). The closure returns `true` to flash a
/// confirmation glyph (copy), `false` for fire-and-forget (regenerate).
@MainActor
struct IconActionButton: View {
    let systemName: String
    let flashSystemName: String?
    let enabled: Bool
    let accessibility: String
    let action: () -> Bool
    @State private var hovering = false
    @State private var flashing = false

    var body: some View {
        Button {
            if action(), flashSystemName != nil {
                flashing = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { flashing = false }
            }
        } label: {
            Image(systemName: flashing ? (flashSystemName ?? systemName) : systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(flashing ? SettingsTheme.wine : (hovering ? SettingsTheme.ink : SettingsTheme.ink2))
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 10).fill(hovering ? SettingsTheme.ink.opacity(0.07) : .clear))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(SettingsTheme.hair, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .onHover { hovering = $0 }
        .accessibilityLabel(accessibility)
    }
}

/// ⌥ 追问 — an affordance, not a button: the actual follow-up is the Option push-to-talk
/// trigger, so this reads as a hint rather than a clickable control.
@MainActor
struct AskMoreHint: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("⌥").font(.system(size: 11, design: .monospaced))
            Text("追问").font(.system(size: 12.5, weight: .semibold))
        }
        .foregroundStyle(SettingsTheme.wine)
        .padding(.horizontal, 13)
        .frame(height: 32)
        .background(Capsule(style: .continuous).fill(SettingsTheme.wine.opacity(0.10)))
        .overlay(Capsule(style: .continuous).strokeBorder(SettingsTheme.wine.opacity(0.28), lineWidth: 1))
        .accessibilityLabel("按 Option 追问")
    }
}
