import SwiftUI

/// 来源核验 demo 的「划词菜单」浮层。选中文字后弹出的真实入口（`SelectionActionMenu`）的脚本复刻：
/// 翻译 / 朗读 / 来源核验（招牌·酒红） / 来源辅助检索 / 任意提问。`highlight` 让来源核验行短暂高亮，
/// 表示「这一项被选中」，随后菜单淡出、跳转知网核验。
struct DemoSwipeMenu: View {
    @Environment(AppearanceStore.self) private var appearance
    let highlight: Bool
    /// When set, rows become tappable and report the picked label (sandbox 划词 flow).
    /// nil = passive display (the FeatureDemo theatre use).
    var onPick: ((String) -> Void)? = nil

    private struct Item: Identifiable {
        let id = UUID()
        let icon: String
        let label: String
        let isVerify: Bool
    }

    private let items: [Item] = [
        Item(icon: "character.bubble", label: "翻译", isVerify: false),
        Item(icon: "speaker.wave.2", label: "朗读", isVerify: false),
        Item(icon: "checkmark.seal", label: "来源核验", isVerify: true),
        Item(icon: "magnifyingglass", label: "来源辅助检索", isVerify: false),
        Item(icon: "plus.bubble", label: "任意提问", isVerify: false),
    ]

    var body: some View {
        let p = appearance.palette
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                if idx > 0 { Rectangle().fill(p.hair).frame(height: 0.5) }
                if let onPick {
                    Button { onPick(item.label) } label: { row(item, p) }
                        .buttonStyle(.plain)
                } else {
                    row(item, p)
                }
            }
        }
        .frame(width: 206)
        .background(p.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(p.hairStrong, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
    }

    private func row(_ item: Item, _ p: SkinPalette) -> some View {
        let isHot = item.isVerify && highlight
        return HStack(spacing: SkinMetrics.sp2) {
            Image(systemName: item.icon)
                .font(.system(size: 12))
                .foregroundStyle(item.isVerify ? p.accent : p.ink2)
                .frame(width: 18)
            Text(item.label)
                .font(.system(size: SkinMetrics.fsFoot, weight: item.isVerify ? .bold : .regular))
                .foregroundStyle(item.isVerify ? p.accent : p.ink)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13).padding(.vertical, 9)
        .background(isHot ? p.accent.opacity(0.14) : .clear)
    }
}
