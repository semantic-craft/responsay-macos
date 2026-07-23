import ResponsayCore
import SwiftUI

// MARK: - 7 · 完成

struct DoneStepView: View {
    @Environment(AppearanceStore.self) private var appearance
    let model: OnboardingModel

    var body: some View {
        let p = appearance.palette
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(LinearGradient(colors: [p.accent, p.accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "checkmark").font(.system(size: 28, weight: .bold)).foregroundStyle(p.onAccent)
            }
            .frame(width: 64, height: 64).padding(.bottom, 6)

            Text(OnboardingStep.done.kicker).font(.system(size: SkinMetrics.fsLabel, weight: .bold)).tracking(1.8).foregroundStyle(p.accent).padding(.top, 6)
            (Text("都").fontWeight(.light) + Text("设好了").fontWeight(.semibold)).font(.system(size: SkinMetrics.fsTitle, weight: .semibold)).foregroundStyle(p.ink).padding(.top, 6)
            Text("按下唤起快捷键，对它说一句话——剩下的交给\(AppBrand.displayName)。").font(.system(size: SkinMetrics.fsBody)).foregroundStyle(p.ink2).padding(.top, 4)

            VStack(spacing: 0) {
                sumRow("皮肤", appearance.skin.displayName + " · " + appearance.skin.tagline, p)
                Divider().background(p.hair)
                sumRow("引擎", model.engineSummary, p)
                Divider().background(p.hair)
                sumRow("快捷键", model.shortcutScheme.summary, p)
            }
            .background(RoundedRectangle(cornerRadius: SkinMetrics.radiusCard).fill(p.card2))
            .overlay(RoundedRectangle(cornerRadius: SkinMetrics.radiusCard).strokeBorder(p.hair, lineWidth: 1))
            .padding(.top, 22)

            // 315: the voice assistant exists but had zero onboarding mentions.
            // Honest one-liner — it needs a cloud BYOK key and a binding the
            // user sets themselves; no defaults invented.
            Text("进阶：在 设置 → 快捷键 给「任意提问」绑一个键——随时开口提问，或选中文字后基于选区改写/摘要/翻译/问答（需云端 Key）。")
                .font(.system(size: SkinMetrics.fsFoot)).foregroundStyle(p.ink3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func sumRow(_ key: String, _ value: String, _ p: SkinPalette, mono: Bool = false) -> some View {
        HStack(spacing: 14) {
            Text(key).font(.system(size: SkinMetrics.fsFoot, weight: .semibold)).foregroundStyle(p.ink3).frame(width: 60, alignment: .leading)
            Text(value).font(mono ? .system(size: SkinMetrics.fsBody, design: .monospaced) : .system(size: SkinMetrics.fsBody, weight: .medium)).foregroundStyle(p.ink)
            Spacer()
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
    }
}
