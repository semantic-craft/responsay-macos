import SwiftUI

struct SettingsSidebar: View {
    @Binding var selection: SettingsSection?
    @Environment(AppearanceStore.self) private var appearanceStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                sidebarGroup("输入", [.general, .hotkeys, .selectionMenu, .rewrite, .dictionary])
                sidebarGroup("模型", [.models, .asr, .llm, .tts, .ocr])
                sidebarGroup("技能", [.legalSkills, .legalConfig, .verify])
                sidebarGroup("系统", [.appearance, .privacy, .data, .storage, .diagnostics, .about])
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
        }
        .scrollContentBackground(.hidden)
        .background(SettingsTheme.sidebar)
    }

    private func sidebarGroup(_ title: LocalizedStringKey,
                              _ items: [SettingsSection]) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Circle().fill(appearanceStore.palette.accent).frame(width: 6, height: 6)
                Text(title)
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(appearanceStore.palette.ink3)
                    .kerning(0.7)
            }
            .padding(.horizontal, 11)
            .padding(.top, 16)
            .padding(.bottom, 5)
            ForEach(items) { sidebarItem($0) }
        }
    }

    private func sidebarItem(_ section: SettingsSection) -> some View {
        let isOn = (selection ?? .general) == section
        let accent = section.domain?.color ?? appearanceStore.palette.accent
        return Button {
            selection = section
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 14))
                    .foregroundStyle(isOn ? accent : appearanceStore.palette.ink3)
                    .frame(width: 18)
                Text(LocalizedStringKey(section.title))
                    .font(.system(size: 14.5))
                    .fontWeight(isOn ? .medium : .regular)
                    .foregroundStyle(isOn ? appearanceStore.palette.ink : appearanceStore.palette.ink2)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 8).fill(isOn ? appearanceStore.palette.card : Color.clear))
            .overlay(alignment: .leading) {
                if isOn {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(accent)
                        .frame(width: 3)
                        .padding(.vertical, 6)
                }
            }
            .shadow(color: isOn ? .black.opacity(0.05) : .clear, radius: 1, y: 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
