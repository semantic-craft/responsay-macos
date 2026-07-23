import SwiftUI

/// Shown when the Fn scheme is active but the macOS Globe/Fn key still has a system
/// action (更改输入法 etc.) that swallows the press. Guides the user to set
/// 「按下🌐键用于」→「不执行任何操作」 — the only reliable fix. See `FnKeyUsage`.
struct FnUsageGuidanceCard: View {
    @Environment(AppearanceStore.self) private var appearance

    var body: some View {
        let p = appearance.palette
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "globe")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(p.onAccent)
                .frame(width: 30, height: 30)
                .background(Circle().fill(p.accent))
            VStack(alignment: .leading, spacing: 6) {
                Text("按 Fn 会切换输入法")
                    .font(.system(size: SkinMetrics.fsCard, weight: .semibold))
                    .foregroundStyle(p.ink)
                Text("macOS 默认把 🌐 / Fn 键用于「更改输入法」，会抢走这次按键。请到 系统设置 → 键盘 →「按下🌐键用于」选「不执行任何操作」，重启后 Fn 就只唤起法言。")
                    .font(.system(size: SkinMetrics.fsFoot))
                    .foregroundStyle(p.ink2)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                Button { FnKeyUsage.openKeyboardSettings() } label: {
                    Text("打开键盘设置")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(p.onAccent)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8).fill(p.accent))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: SkinMetrics.radiusCard).fill(p.accentWash))
        .overlay(RoundedRectangle(cornerRadius: SkinMetrics.radiusCard).strokeBorder(p.accentLine, lineWidth: 1))
    }
}

#Preview {
    FnUsageGuidanceCard().padding(28).frame(width: 520)
        .environment(AppearanceStore())
}
