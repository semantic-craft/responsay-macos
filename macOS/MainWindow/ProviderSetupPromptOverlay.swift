import SwiftUI
import ResponsayCore

struct ProviderSetupPromptOverlay: View {
    var onLater: () -> Void
    var onOpenSettings: () -> Void

    @Environment(AppearanceStore.self) private var appearanceStore

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()

            card
                .transition(.scale(scale: 0.97).combined(with: .opacity))
        }
        .animation(.spring(duration: 0.26), value: true)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(appearanceStore.palette.accentWash)
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(systemName: "gearshape")
                            .font(.system(size: 16))
                            .foregroundStyle(appearanceStore.palette.accent)
                    )
                Text("设置模型")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(appearanceStore.palette.ink)
            }
            .padding(.bottom, 12)

            // Body
            Text("还没有配置 LLM 模型，改写、翻译、地道外文等功能暂时无法使用。")
                .font(.system(size: 12.5))
                .foregroundStyle(appearanceStore.palette.ink3)
                .lineSpacing(4)

            // Actions
            HStack(spacing: 8) {
                Spacer()
                Button(action: onLater) {
                    Text("稍后")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(appearanceStore.palette.ink3)
                        .padding(.horizontal, 13).padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(appearanceStore.palette.card)
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(SettingsTheme.hairStrong, lineWidth: 0.5))
                        )
                }
                .buttonStyle(.plain)

                Button(action: onOpenSettings) {
                    Text("去设置")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8).fill(appearanceStore.palette.ink))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 18)
        }
        .padding(20)
        .frame(width: 360)
        // 311: family chrome + hero shadow token (was a hand-rolled 0.15/24/8).
        .warmCardSurface(shadow: .hero)
    }
}
