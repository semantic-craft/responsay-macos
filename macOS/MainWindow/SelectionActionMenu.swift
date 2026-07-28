import SwiftUI
import ResponsayCore

/// 划词菜单 — Claude Design handoff "Selection Menu", **Variant B (带标签/labeled)**.
///
/// Two-tier progressive disclosure in a warm-paper popover with a beak anchored to
/// the selection:
///   1. **Resting** = an instant icon row — `[翻译] [朗读] | [⋯]` (icon-only, hover =
///      accent-tinted). Tapping ⋯ expands.
///   2. **Expanded** = labeled smart rows (icon坑 · 标题 + 一行说明): 来源核验 / 来源辅助检索 /
///      任意提问 / (加入词典), plus each enabled 划词生成 技能 as its own row. The list is flat —
///      `items` arrives already resolved from the saved `SelectionMenuLayout` (order + show/hide).
///   3. **Bottom bar** = 管理技能… (left, opens the skills library) + ✕ close (right).
///
/// Tokens are aligned to the designer's shenda-skin defaults (light + dark). The view
/// owns its expand state and reports its size so the host panel can resize.
struct SelectionActionMenu: View {
    /// All visible menu items, resolved from the user's `SelectionMenuLayout` (order + show/hide) —
    /// built-in actions (incl. 翻译/朗读) and enabled skills, flattened. The first few render as the
    /// resting icon row; tapping ⋯ reveals the rest as labeled rows.
    let items: [SelectionMenuItem]
    var onPick: (SelectionAction) -> Void = { _ in }
    var onPickSkill: (String) -> Void = { _ in }
    var onCustomize: () -> Void = {}
    var onClose: () -> Void = {}
    var onLayoutChange: (CGSize) -> Void = { _ in }

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    private var p: MenuPalette { scheme == .dark ? .dark : .light }

    /// How many leading items render as quick icons in the resting row; the rest expand as labels.
    private static let iconRowCount = 3
    private var iconRowItems: [SelectionMenuItem] { Array(items.prefix(Self.iconRowCount)) }
    private var labeledItems: [SelectionMenuItem] { Array(items.dropFirst(Self.iconRowCount)) }

    var body: some View {
        VStack(spacing: 0) {
            beak
            VStack(alignment: .leading, spacing: 0) {
                instantRow
                if expanded {
                    if !labeledItems.isEmpty { smartRows }
                    bottomBar
                }
            }
            .background(card(radius: 14))
        }
        .padding(16)               // room for the soft shadow + the outset beak
        .fixedSize()
        .background(GeometryReader { geo in
            Color.clear
                .onAppear { onLayoutChange(geo.size) }
                .onChange(of: geo.size) { _, new in onLayoutChange(new) }
        })
    }

    // MARK: - The beak / anchor triangle (11×11 square rotated 45°, points up)

    private var beak: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(p.paper)
            .frame(width: 11, height: 11)
            .rotationEffect(.degrees(45))
            .frame(width: 16, height: 8, alignment: .bottom)
            .clipped()
            .offset(y: 1)
    }

    // MARK: - Tier 1 · resting icon row — the first few items as quick icons + [⋯]

    private var instantRow: some View {
        HStack(spacing: 4) {
            ForEach(iconRowItems) { item in
                iconButton(item.systemImage, label: item.title) { pick(item) }
            }
            verticalDivider
            iconButton("ellipsis", label: expanded ? "收起更多操作" : "更多操作") {
                withExpandAnimation { expanded.toggle() }
            }
        }
        .padding(7)
    }

    private func iconButton(_ name: String, label: String, action: @escaping () -> Void) -> some View {
        MenuButton(hoverFill: p.hover, corner: 9, action: action) {
            Image(systemName: name)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(p.ink)
                .frame(width: 34, height: 34)
        }
        .accessibilityLabel(label)
    }

    private var verticalDivider: some View {
        Rectangle().fill(p.line).frame(width: 1, height: 22).padding(.horizontal, 2)
    }

    // MARK: - Tier 2 · labeled smart rows

    private var smartRows: some View {
        VStack(alignment: .leading, spacing: 2) {
            Rectangle().fill(p.line).frame(height: 1).padding(.horizontal, 2).padding(.bottom, 2)
            ForEach(labeledItems) { item in
                smartRow(item)
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 2)
        .padding(.bottom, 4)
    }

    /// One smart row — a built-in action or an enabled skill (flattened, per the configurable
    /// layout). Full-row hover tint; 来源核验 carries a 推荐 tag. Picking routes to the right callback.
    private func smartRow(_ item: SelectionMenuItem) -> some View {
        MenuButton(hoverFill: p.hover, corner: 9, action: { pick(item) }) {
            smartRowContent(icon: item.systemImage, title: item.title,
                            desc: description(for: item), recommended: isRecommended(item))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
        .accessibilityHint(description(for: item))
        .accessibilityAddTraits(.isButton)
    }

    private func pick(_ item: SelectionMenuItem) {
        switch item {
        case let .action(action): onPick(action)
        case let .skill(id, _): onPickSkill(id)
        }
    }

    /// 来源核验 is the one recommended (wine-tagged) action.
    private func isRecommended(_ item: SelectionMenuItem) -> Bool {
        item == .action(.verify)
    }

    /// Built-in actions carry a one-line hint; flattened skills rely on their title alone.
    private func description(for item: SelectionMenuItem) -> String {
        switch item {
        case let .action(action): return action.menuDescription
        case .skill: return ""
        }
    }

    private func smartRowContent(icon name: String, title: String, desc: String,
                                 recommended: Bool) -> some View {
        HStack(spacing: 11) {
            iconWell(name)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(p.ink)
                    if recommended { recommendedTag }
                }
                if !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 11.5))
                        .foregroundStyle(p.ink2)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 46)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The accent-tinted icon坑 — 30×30, rounded 8, accent @ 12%.
    private func iconWell(_ name: String) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(p.accentWell)
            .frame(width: 30, height: 30)
            .overlay(
                Image(systemName: name)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(p.accent)
            )
    }

    private var recommendedTag: some View {
        Text("推荐")
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(p.accent)
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .background(Capsule().fill(p.accentWell))
    }

    // MARK: - Bottom bar · 自定义菜单…  /  ✕

    private var bottomBar: some View {
        HStack(spacing: 0) {
            MenuButton(hoverFill: p.hover, corner: 8, action: onCustomize) {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 12, weight: .regular))
                    Text("自定义菜单…").font(.system(size: 12.5, weight: .regular))
                }
                .foregroundStyle(p.ink2)
                .padding(.horizontal, 8).padding(.vertical, 6)
            }
            .accessibilityLabel("自定义划词菜单")

            Spacer(minLength: 8)

            MenuButton(hoverFill: p.hover, corner: 8, action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(p.ink2)
                    .frame(width: 26, height: 26)
            }
            .accessibilityLabel("关闭")
        }
        .padding(.horizontal, 8)
        .padding(.top, 2)
        .padding(.bottom, 8)
        .overlay(alignment: .top) {
            Rectangle().fill(p.line).frame(height: 1).padding(.horizontal, 8)
        }
    }

    // MARK: - Shared bits

    private func withExpandAnimation(_ body: () -> Void) {
        if reduceMotion {
            body()
        } else {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) { body() }
        }
    }

    private func card(radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(p.paper)
            .shadow(color: p.shadow1, radius: p.shadow1Radius, y: p.shadow1Y)
            .shadow(color: p.shadow2, radius: p.shadow2Radius, y: p.shadow2Y)
    }
}

/// One 划词生成 技能 surfaced as its own 划词菜单 row (picking it runs the skill by id).
struct SelectionGenerationSkill: Identifiable, Hashable {
    let id: String
    let title: String
}

// MARK: - Hover-highlight button

private struct MenuButton<Label: View>: View {
    var baseFill: Color = .clear
    var hoverFill: Color
    var corner: CGFloat
    let action: () -> Void
    @ViewBuilder var label: () -> Label
    @State private var hovering = false

    init(
        baseFill: Color = .clear,
        hoverFill: Color,
        corner: CGFloat,
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.baseFill = baseFill
        self.hoverFill = hoverFill
        self.corner = corner
        self.action = action
        self.label = label
    }

    var body: some View {
        Button(action: action) {
            label()
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: corner).fill(hovering ? hoverFill : baseFill))
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: corner))
        .onHover { hovering = $0 }
    }
}

// MARK: - Palette (shenda-skin tokens from the Variant B handoff, light + dark)

private struct MenuPalette {
    let paper, ink, ink2, ink3, line, accent, accentWell, hover, well: Color
    let shadow1, shadow2: Color
    let shadow1Radius, shadow1Y, shadow2Radius, shadow2Y: CGFloat

    static let light = MenuPalette(
        paper: .hex(0xFBF9F5),
        ink: .hex(0x2A2622), ink2: .hex(0x6B6A64), ink3: .hex(0x9A9387),
        line: .hex(0x2A2622, 0.12),
        accent: .hex(0xA82C53),
        accentWell: .hex(0xA82C53, 0.12),
        hover: .hex(0xA82C53, 0.11),
        well: .hex(0x2A2622, 0.05),
        shadow1: .hex(0x2A2622, 0.18), shadow2: .hex(0x2A2622, 0.12),
        shadow1Radius: 15, shadow1Y: 12, shadow2Radius: 1, shadow2Y: 1)

    static let dark = MenuPalette(
        paper: .hex(0x262321),
        ink: .hex(0xECE4D8), ink2: .hex(0xA89E90), ink3: .hex(0x766D62),
        line: .hex(0xECE4D8, 0.12),
        accent: .hex(0xE06A8E),
        accentWell: .hex(0xE06A8E, 0.12),
        hover: .hex(0xE06A8E, 0.16),
        well: .hex(0xECE4D8, 0.05),
        shadow1: .hex(0x000000, 0.46), shadow2: .hex(0x000000, 0.42),
        shadow1Radius: 17, shadow1Y: 12, shadow2Radius: 1, shadow2Y: 1)
}

private extension Color {
    /// 0xRRGGBB hex with optional opacity, in the sRGB space.
    static func hex(_ value: UInt32, _ opacity: Double = 1) -> Color {
        Color(.sRGB,
              red: Double((value >> 16) & 0xFF) / 255,
              green: Double((value >> 8) & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255,
              opacity: opacity)
    }
}
