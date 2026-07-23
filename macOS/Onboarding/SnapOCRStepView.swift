import ResponsayCore
import SwiftUI

// MARK: - 4 · 截图翻译

struct SnapOCRStepView: View {
    @Environment(AppearanceStore.self) private var appearance
    let model: OnboardingModel

    var body: some View {
        let p = appearance.palette
        VStack(alignment: .leading, spacing: 24) {
            OBStepHeader(
                kicker: OnboardingStep.snapOCR.kicker,
                title: Text("杀手级功能：").fontWeight(.light) + Text("截图翻译").fontWeight(.semibold),
                lede: "遇到图片、受保护的 PDF 或无法选中的文字？用截图翻译提取文字，并忠实准确地翻译成目标语言。")

            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(p.accentWash)
                        Image(systemName: "viewfinder").font(.system(size: 28)).foregroundStyle(p.accent)
                    }
                    .frame(width: 60, height: 60)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("全屏随时可用").font(.system(size: SkinMetrics.fsCard, weight: .semibold)).foregroundStyle(p.ink)
                        Text("你可以为它绑定全局快捷键（下一步），随时按下，框选屏幕即可取词。")
                            .font(.system(size: SkinMetrics.fsFoot)).foregroundStyle(p.ink2)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: SkinMetrics.radiusCard).fill(p.card2))
                .overlay(RoundedRectangle(cornerRadius: SkinMetrics.radiusCard).strokeBorder(p.hair, lineWidth: 1))

                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(p.accentWash)
                        Image(systemName: "lock.shield").font(.system(size: 28)).foregroundStyle(p.accent)
                    }
                    .frame(width: 60, height: 60)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("用到时再授权").font(.system(size: SkinMetrics.fsCard, weight: .semibold)).foregroundStyle(p.ink)
                        Text("现在无需开启屏幕录制。第一次按下「截图翻译」时系统才会请求——授权后按一下「重启 Responsay」即可生效。")
                            .font(.system(size: SkinMetrics.fsFoot)).foregroundStyle(p.ink2)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: SkinMetrics.radiusCard).fill(p.card2))
                .overlay(RoundedRectangle(cornerRadius: SkinMetrics.radiusCard).strokeBorder(p.hair, lineWidth: 1))
            }
        }
    }
}
