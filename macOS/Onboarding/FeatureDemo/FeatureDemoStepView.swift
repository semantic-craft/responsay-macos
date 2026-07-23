import SwiftUI

/// 看演示 (step 7): **one feature per screen**. The footer's 继续/返回 page through the
/// 五大模块 one at a time (mirrors the 实操体验 `sandboxSequence` pattern) instead of
/// stacking all five demos into one long scroll. The Overview replay sheet still shows
/// them all together via `FeatureDemoShowcase(layout: .sheet)`.
struct FeatureDemoStepView: View {
    let model: OnboardingModel

    private var modules: [FeatureDemoShowcase.Module] { FeatureDemoShowcase.modules }
    private var index: Int { min(max(model.demoIndex, 0), modules.count - 1) }

    var body: some View {
        let module = modules[index]
        VStack(alignment: .leading, spacing: 20) {
            OBStepHeader(
                kicker: OnboardingStep.demo.kicker,
                title: Text("先看一遍").fontWeight(.light) + Text("五大模块").fontWeight(.semibold),
                lede: "一个功能一屏——用下方「继续」逐个看完听写、语音翻译、任意提问、划词菜单、截图识别。划词菜单里的来源核验会跳到知网核对论文原文。")

            DemoPagerBar(index: index, count: modules.count, model: model)

            ModuleCard(module: module, layout: .onboarding)
                .id(index)              // recreate so the hero animation replays on switch
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.25), value: model.demoIndex)
    }
}

/// "功能 0N / 05" + tappable dots — the screen-position indicator for the per-feature pager.
private struct DemoPagerBar: View {
    @Environment(AppearanceStore.self) private var appearance
    let index: Int
    let count: Int
    let model: OnboardingModel

    var body: some View {
        let p = appearance.palette
        HStack(spacing: SkinMetrics.sp3) {
            Text(String(format: "功能 %02d / %02d", index + 1, count))
                .font(.system(size: SkinMetrics.fsLabel, weight: .bold)).tracking(1.4)
                .monospacedDigit()
                .foregroundStyle(p.accent)
            HStack(spacing: 7) {
                ForEach(0..<count, id: \.self) { i in
                    Button { model.demoIndex = i } label: {
                        Capsule()
                            .fill(i == index ? p.accent : p.hairStrong)
                            .frame(width: i == index ? 22 : 8, height: 8)
                    }
                    .buttonStyle(.plain)
                    .help(FeatureDemoShowcase.modules[i].title)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    ScrollView {
        FeatureDemoStepView(model: OnboardingModel()).padding(32)
    }
    .frame(width: 624, height: 700)
    .environment(AppearanceStore())
}
