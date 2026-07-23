import SwiftUI

/// Settings · 快捷键. One unified recorder card (`UnifiedShortcutSection`) — one row per function,
/// record Fn / 右 Option / Hyper + 字母数字 in place — plus the 划词互动 card. Replaced the old
/// three-card split (Fn 键 / 右 Option 键 / 组合键); those section files are now unused.
struct SettingsShortcutPane: View {
    @Environment(AppearanceStore.self) private var appearanceStore

    @Binding var shortcutScheme: String
    let shortcutSettingsStore: ShortcutSettingsStore

    private static let keycapReference: [(String, String)] = [
        ("fn", "地球 / Fn"), ("⌥R", "右 Option"), ("⌘", "Command"), ("⌥", "Option"),
        ("⌃", "Control"), ("⇧", "Shift"), ("Space", "空格"),
    ]

    var body: some View {
        SettingsPaneColumn {
            SettingsPaneHeader(title: "快捷键", desc: "为每个触发键挑选它启动的动作。")

            UnifiedShortcutSection(store: shortcutSettingsStore)
            SelectionInteractionSection()

            WarmCard {
                GroupLabel(text: "键帽对照")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(Self.keycapReference, id: \.0) { cap, desc in
                        HStack(spacing: 9) {
                            Text(cap)
                                .font(SettingsTheme.mono)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 6).fill(appearanceStore.palette.card))
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(SettingsTheme.fieldBorder, lineWidth: 1))
                            Text(desc).font(SettingsTheme.footnote).foregroundStyle(appearanceStore.palette.ink2)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
        .navigationTitle("快捷键")
    }
}
