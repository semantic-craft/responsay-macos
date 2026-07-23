import ResponsayCore
import SwiftUI

// MARK: - 5 · 设快捷键

struct HotkeyStepView: View {
    @Environment(AppearanceStore.self) private var appearance
    let model: OnboardingModel

    var body: some View {
        let p = appearance.palette
        VStack(alignment: .leading, spacing: 24) {
            OBStepHeader(
                kicker: OnboardingStep.hotkey.kicker,
                title: Text("选一套").fontWeight(.light) + Text("快捷键").fontWeight(.semibold) + Text("方案").fontWeight(.light),
                lede: "Responsay 有两套预设触发方式——点按开始说话，再点按结束并插入。之后都能在设置里逐项改。")
            VStack(spacing: 12) {
                ForEach(ShortcutScheme.allCases, id: \.self) { s in
                    OBOptionCard(title: s.title, detail: s.detail, meta: s.meta,
                                 isSelected: model.shortcutScheme == s) { model.shortcutScheme = s }
                }
            }

            HStack(spacing: 9) {
                ForEach(model.shortcutScheme.keycaps, id: \.self) { k in
                    Text(k).font(.system(size: 20, weight: .semibold, design: .monospaced)).foregroundStyle(p.onAccent)
                        .frame(minWidth: 46).frame(height: 48).padding(.horizontal, 14)
                        .background(RoundedRectangle(cornerRadius: 10).fill(p.accent))
                }
                Text(model.shortcutScheme == .fn ? "点按 Fn 开始，再点按结束" : "按下组合键，开始说")
                    .font(.system(size: SkinMetrics.fsFoot)).foregroundStyle(p.ink2)
                    .padding(.leading, 6)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(RoundedRectangle(cornerRadius: SkinMetrics.radiusCard).fill(p.field))
            .overlay(RoundedRectangle(cornerRadius: SkinMetrics.radiusCard).strokeBorder(p.hairStrong, lineWidth: 1))

            if model.shortcutScheme == .fn && FnKeyUsage.stealsFnPress {
                FnUsageGuidanceCard()
            }

            HotkeyCalibrationCard(scheme: model.shortcutScheme)
        }
    }
}
