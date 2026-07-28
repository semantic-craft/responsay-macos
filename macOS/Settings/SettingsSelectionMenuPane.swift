import SwiftUI
import ResponsayCore
import UniformTypeIdentifiers

/// 设置 › 划词菜单 — order + show/hide the configurable smart rows (built-in actions + enabled
/// skills) that the 划词菜单 shows under 翻译/朗读. Drag to reorder, toggle to show/hide; every
/// change writes the shared `SelectionMenuLayout`. Skills are *enabled* in the 技能平台 (link below);
/// here you only arrange where they appear — no duplicate enable switch.
///
/// Uses the shared spacious settings chrome (`SettingsPaneColumn` + `SettingsPaneHeader` +
/// `WarmCard`) so this pane sits on the same ivory card surface and centered column as every
/// other pane — the old bare full-width `List` left the rows on the raw parchment background.
struct SettingsSelectionMenuPane: View {
    @Environment(AppearanceStore.self) private var appearanceStore

    /// Jump to the 技能平台 so the user can enable more skills (they then appear here).
    var openSkillsLibrary: () -> Void = {}

    @State private var rows: [SelectionMenuLayout.EditorRow] = []
    @State private var loaded = false
    @State private var dragging: SelectionMenuLayout.EditorRow?

    private var palette: SkinPalette { appearanceStore.palette }

    var body: some View {
        SettingsPaneColumn {
            SettingsPaneHeader(
                title: "划词菜单",
                desc: "选中文字后按快捷键弹出的菜单。拖动排序，开关决定每一项是否出现。")

            WarmCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach($rows) { $row in
                        if row.id != rows.first?.id { WarmDivider() }
                        rowView(for: $row)
                            .contentShape(Rectangle())
                            .onDrag {
                                dragging = row
                                return NSItemProvider(object: row.id as NSString)
                            }
                            .onDrop(of: [.text], delegate: RowDropDelegate(
                                target: row, rows: $rows, dragging: $dragging, onChange: save))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("关闭某一项只是把它从划词菜单里隐藏，不会停用对应功能。")
                    .font(SettingsTheme.footnote)
                    .foregroundStyle(palette.ink2)
                Text("带「技能平台」标记的项来自技能平台，需在那里激活后才会出现；这里的开关只调整菜单里的显示与顺序。")
                    .font(SettingsTheme.footnote)
                    .foregroundStyle(palette.ink2)
                Button(action: openSkillsLibrary) {
                    HStack(spacing: 6) {
                        Image(systemName: "scalemass")
                        Text("在技能平台里启用更多技能")
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(palette.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("划词菜单")
        .onAppear { loadIfNeeded() }
    }

    private func rowView(for row: Binding<SelectionMenuLayout.EditorRow>) -> some View {
        let item = row.wrappedValue.item
        return HStack(spacing: 11) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12))
                .foregroundStyle(palette.ink3)
            iconWell(item.systemImage)
            Text(item.title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(palette.ink)
            if item == .action(.verify) { tag("推荐") }
            if isPlatformGated(item) { tag("技能平台") }
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(
                get: { row.wrappedValue.visible },
                set: { row.wrappedValue.visible = $0; save() }))
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel("在划词菜单显示 \(item.title)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// Wine-tinted icon tile, matching `CapabilityHeader`'s tile (shared theme tokens).
    private func iconWell(_ name: String) -> some View {
        RoundedRectangle(cornerRadius: SkinMetrics.radiusSmall)
            .fill(SettingsTheme.wineTint)
            .frame(width: 28, height: 28)
            .overlay(Image(systemName: name).font(.system(size: 14)).foregroundStyle(SettingsTheme.wine))
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(palette.accent)
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .background(Capsule().fill(palette.accent.opacity(0.12)))
    }

    /// Platform-gated items — skill-backed actions (引注源验 / 来源辅助检索), the rule-driven
    /// 规范排版 and enabled practice skills — surface here only because they're 激活 in the 技能平台,
    /// so they carry a「技能平台」marker and disappear if turned off there. The fixed functions
    /// (翻译 / 朗读 / 加入词典 / 任意提问) are never gated.
    private func isPlatformGated(_ item: SelectionMenuItem) -> Bool {
        switch item {
        case let .action(action):
            if case .always = action.gate { return false }
            return true
        case .skill:
            return true
        }
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        // Same 技能平台 gate as the live menu: the gated actions (引注源验/来源辅助检索/规范排版) list
        // here only when 激活, so 拖动排序 stays in sync with what the menu actually shows.
        let actions = SelectionMenuGate().available(from: SelectionMenuLayout.configurableActions)
        let skills = LegalSkillLibrary().enabledPracticeSkills()
            .map { (id: $0.id, title: $0.metadata.title) }
        rows = SelectionMenuLayoutStore.load().editorRows(
            availableActions: actions,
            availableSkills: skills)
    }

    private func save() {
        SelectionMenuLayoutStore.save(SelectionMenuLayout.from(rows: rows))
    }
}

/// Drag-reorder for the rows now that they live in a `WarmCard` VStack instead of a `List`
/// (a height-filling `List` can't sit inside the content-sized card column). Small bounded
/// list, so the standard onDrag/onDrop delegate is enough — no auto-scroll needed.
private struct RowDropDelegate: DropDelegate {
    let target: SelectionMenuLayout.EditorRow
    @Binding var rows: [SelectionMenuLayout.EditorRow]
    @Binding var dragging: SelectionMenuLayout.EditorRow?
    let onChange: () -> Void

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging.id != target.id,
              let from = rows.firstIndex(of: dragging),
              let to = rows.firstIndex(of: target) else { return }
        withAnimation {
            rows.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        onChange()
        return true
    }
}
