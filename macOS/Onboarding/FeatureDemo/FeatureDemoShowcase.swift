import SwiftUI

enum FeatureDemoShowcaseLayout {
    case onboarding
    case sheet

    var heroHeight: CGFloat {
        switch self {
        case .onboarding: 330
        case .sheet: 360
        }
    }

    var standardHeight: CGFloat {
        switch self {
        case .onboarding: 226
        case .sheet: 246
        }
    }

    var copyWidth: CGFloat {
        switch self {
        case .onboarding: 176
        case .sheet: 206
        }
    }
}

/// The onboarding "demo theatre", organized as **五大模块** (one hero animation each). The Overview
/// replay sheet additionally shows a 更多演示 group with the secondary selection/legal demos, so the
/// extra (tested) kinds stay reachable.
struct FeatureDemoShowcase: View {
    var layout: FeatureDemoShowcaseLayout = .onboarding

    struct Module: Identifiable {
        let number: Int
        let hotkey: String
        let title: String
        let blurb: String
        let hero: FeatureDemoKind
        var id: Int { number }
    }

    static let modules: [Module] = [
        Module(number: 1, hotkey: "轻点 Fn", title: "听写",
               blurb: "说话，文字直接进光标。中文进中文、英文进英文，默认帮你整理成通顺文字，写入任意 App——不用切窗口、不用复制粘贴。",
               hero: .dictate),
        Module(number: 2, hotkey: "Fn Shift", title: "语音翻译",
               blurb: "在微信、企业微信里说中文，英文译文直接落进当前输入框，发给境外同事或对方律师。",
               hero: .translate),
        Module(number: 3, hotkey: "Fn Space", title: "任意提问",
               blurb: "问一个问题或说一个想法，结果出现在屏幕中央的只读答卡里——可以朗读、复制、重新生成、追问，但不会改动你的文档。",
               hero: .english),
        Module(number: 4, hotkey: "划词键 + 拖选", title: "划词菜单 · 来源核验",
               blurb: "选中任意文字弹出划词菜单：翻译、朗读，以及法律招牌技能来源核验——把引文里的论文、法条提取成坐标，跳到知网核对，把命中的来源证据带回来。",
               hero: .verify),
        Module(number: 5, hotkey: "截图键", title: "截图识别",
               blurb: "框选屏幕上任意一块区域，把图片里的文字取出来进可编辑面板——复制、智能分段，或换引擎再识别、翻译。扫描件、PDF 截图都能取字。",
               hero: .snapOCR),
    ]

    /// Secondary demos (still real & tested) surfaced only in the replay sheet's 更多演示 group.
    static let extraKinds: [FeatureDemoKind] = [.selectTranslate, .coach, .keywords, .fallback]

    var body: some View {
        VStack(alignment: .leading, spacing: SkinMetrics.sp5) {
            ForEach(Self.modules) { ModuleCard(module: $0, layout: layout) }
            if layout == .sheet {
                MoreDemosSection(kinds: Self.extraKinds, layout: layout)
            }
        }
    }
}

// MARK: - Module card (hero per module)

struct ModuleCard: View {
    @Environment(AppearanceStore.self) private var appearance
    let module: FeatureDemoShowcase.Module
    let layout: FeatureDemoShowcaseLayout

    private var isFlagship: Bool { module.hero == .verify }

    var body: some View {
        let p = appearance.palette
        VStack(alignment: .leading, spacing: SkinMetrics.sp3) {
            header(p)
            FeatureDemoView(kind: module.hero)
                .frame(maxWidth: .infinity)
                .frame(height: layout.heroHeight)
        }
        .padding(SkinMetrics.sp4)
        .background(
            RoundedRectangle(cornerRadius: SkinMetrics.radiusCard)
                .fill(LinearGradient(colors: [p.card, p.card2], startPoint: .top, endPoint: .bottom))
        )
        .overlay(
            RoundedRectangle(cornerRadius: SkinMetrics.radiusCard)
                .strokeBorder(isFlagship ? p.accentLine : p.hair, lineWidth: isFlagship ? 1.5 : 1)
        )
    }

    private func header(_ p: SkinPalette) -> some View {
        VStack(alignment: .leading, spacing: SkinMetrics.sp1) {
            HStack(spacing: SkinMetrics.sp2) {
                Text(String(format: "模块 %02d", module.number))
                    .font(.system(size: SkinMetrics.fsLabel, weight: .bold)).tracking(1.4)
                    .foregroundStyle(p.accent)
                Text(module.hotkey)
                    .font(.system(size: SkinMetrics.fsLabel, weight: .semibold, design: .monospaced))
                    .foregroundStyle(p.ink2)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(p.card2, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(p.hair, lineWidth: 0.5))
                if isFlagship {
                    Spacer(minLength: 0)
                    Text("招牌技能")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(p.onAccent)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(p.accent))
                }
            }
            Text(module.title)
                .font(.system(size: SkinMetrics.fsCard, weight: .bold)).foregroundStyle(p.ink)
            Text(module.blurb)
                .font(.system(size: SkinMetrics.fsFoot)).foregroundStyle(p.ink2)
                .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 更多演示 (replay sheet only)

private struct MoreDemosSection: View {
    @Environment(AppearanceStore.self) private var appearance
    let kinds: [FeatureDemoKind]
    let layout: FeatureDemoShowcaseLayout

    var body: some View {
        let p = appearance.palette
        VStack(alignment: .leading, spacing: SkinMetrics.sp3) {
            VStack(alignment: .leading, spacing: 2) {
                Text("更多演示")
                    .font(.system(size: SkinMetrics.fsLabel, weight: .bold)).tracking(1.4)
                    .foregroundStyle(p.accent)
                Text("选区翻译、选区改写、检索词生成、搜索引擎兜底——按需展开")
                    .font(.system(size: SkinMetrics.fsFoot)).foregroundStyle(p.ink3)
            }
            ForEach(kinds) { ExtraDemoRow(kind: $0, layout: layout) }
        }
    }
}

private struct ExtraDemoRow: View {
    @Environment(AppearanceStore.self) private var appearance
    let kind: FeatureDemoKind
    let layout: FeatureDemoShowcaseLayout

    private var script: FeatureDemoScript { .script(for: kind) }

    var body: some View {
        let p = appearance.palette
        HStack(alignment: .top, spacing: SkinMetrics.sp3) {
            VStack(alignment: .leading, spacing: SkinMetrics.sp1) {
                Text(script.kicker)
                    .font(.system(size: SkinMetrics.fsLabel, weight: .bold)).tracking(1.4)
                    .foregroundStyle(p.accent)
                Text(script.title)
                    .font(.system(size: SkinMetrics.fsCard, weight: .semibold)).foregroundStyle(p.ink)
                Text(script.blurb)
                    .font(.system(size: SkinMetrics.fsFoot)).foregroundStyle(p.ink2)
                    .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: layout.copyWidth, alignment: .leading)

            FeatureDemoView(kind: kind)
                .frame(maxWidth: .infinity)
                .frame(height: layout.standardHeight)
        }
        .padding(SkinMetrics.sp3)
        .background(
            RoundedRectangle(cornerRadius: SkinMetrics.radiusCard)
                .fill(LinearGradient(colors: [p.card, p.card2], startPoint: .top, endPoint: .bottom))
        )
        .overlay(
            RoundedRectangle(cornerRadius: SkinMetrics.radiusCard).strokeBorder(p.hair, lineWidth: 1)
        )
    }
}

#Preview {
    ScrollView {
        FeatureDemoShowcase(layout: .sheet).padding(28)
    }
    .frame(width: 900, height: 1000)
    .environment(AppearanceStore())
}
