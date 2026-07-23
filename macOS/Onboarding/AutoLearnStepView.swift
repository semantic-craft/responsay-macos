import ResponsayCore
import SwiftUI

// MARK: - 自动学习（从你的纠正里学词）+ 本机数据说明

/// Surfaces the auto-learn-hotwords opt-in during onboarding instead of leaving it OFF and buried
/// in Settings (the biasing-seam audit, 2026-06-20, found this is the main lever that makes the
/// hotword flywheel actually run for a default user). Also carries the local-data reassurance:
/// learned terms stay on-device, and the app is local-first unless the user configures an API key.
struct AutoLearnStepView: View {
    @Environment(AppearanceStore.self) private var appearance
    let model: OnboardingModel

    var body: some View {
        let p = appearance.palette
        VStack(alignment: .leading, spacing: 20) {
            OBStepHeader(
                kicker: OnboardingStep.autoLearn.kicker,
                title: Text("自动").fontWeight(.light) + Text("学习").fontWeight(.semibold),
                lede: "你每次把识别错的词改对，法言可以记住，下次直接出对的——越用越准。要不要开？")

            VStack(spacing: 12) {
                OBOptionCard(title: "开启（推荐）",
                             detail: "你改对一个反复识别错的专有名词（比如把「应然」改成对的写法），它就悄悄记住、加进识别词典，下次直接出对的。学到的词随时能在 识别词典 里删。",
                             meta: "越用越准",
                             isSelected: model.autoLearnEnabled) { model.autoLearnEnabled = true }
                OBOptionCard(title: "先不开",
                             detail: "保持现状，不从你的修改里学词。以后随时可在 设置 →「语音识别」里打开。",
                             meta: "保持现状",
                             isSelected: !model.autoLearnEnabled) { model.autoLearnEnabled = false }
            }

            // 本机数据说明 —— 用户明确要求在此处讲清「数据都保留在本机（除非配置 API key）」。
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.fill").font(.system(size: 13)).foregroundStyle(p.accent)
                Text("你纠正学到的词只存在这台 Mac（识别词典，随时可删），不传任何服务器。法言本机优先：没配 API key 时，听写、改写走 Apple 系统或离线模型，全程不出本机；只有你自己配了某家云服务商的 Key，对应的语音 / 文字才会直接发给你选的那一家——你的密钥、没有中间服务器。")
                    .font(.system(size: SkinMetrics.fsFoot)).foregroundStyle(p.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: SkinMetrics.radiusSmall).fill(p.card2))
            .overlay(RoundedRectangle(cornerRadius: SkinMetrics.radiusSmall).strokeBorder(p.hair, lineWidth: 1))

            // Auto-learn observes your post-insertion edits through Accessibility (granted in 开权限).
            // Without it the flywheel silently no-ops (audit), so flag the gap honestly when ON.
            if model.autoLearnEnabled && !model.granted.contains(.accessibility) {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 13)).foregroundStyle(p.accent)
                    Text("自动学习要靠「辅助功能」权限观察你的修改——回上一步「开权限」开启它，否则学不到词。")
                        .font(.system(size: SkinMetrics.fsFoot)).foregroundStyle(p.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: SkinMetrics.radiusSmall).fill(p.accentWash))
                .overlay(RoundedRectangle(cornerRadius: SkinMetrics.radiusSmall).strokeBorder(p.accentLine, lineWidth: 1))
            }
        }
        .task { model.refreshPermissions() }
    }
}
