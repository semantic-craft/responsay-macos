import ResponsayCore
import SwiftUI

// The onboarding step bodies, one step per file. Step 2 captures the primary use case,
// engine = offline-vs-cloud capability detail, 试一次 = adaptive by config.

// MARK: - 1 · 选皮肤

struct SkinStepView: View {
    @Environment(AppearanceStore.self) private var appearance
    let model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            OBStepHeader(
                kicker: OnboardingStep.skin.kicker,
                title: Text("选一身").fontWeight(.light) + Text("皮肤").fontWeight(.semibold),
                lede: "版式、间距、字号都不变——只换一个颜色世界。点一下即刻看到整窗重新着色，之后随时能在偏好设置里改回来。")
            // 3 across, wrapping: a single row stopped fitting once the skins passed five —
            // the stage is 544pt wide and a card's name row needs ~175pt, so the extras were
            // squeezed into vertical text and then clipped outright. The stage already scrolls.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3),
                      spacing: 16) {
                ForEach(Skin.allCases) { s in
                    OBSkinCard(skin: s, isSelected: appearance.skin == s) {
                        withAnimation(.easeInOut(duration: 0.35)) { appearance.skin = s }
                    }
                }
            }
        }
    }
}
