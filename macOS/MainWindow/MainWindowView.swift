import SwiftUI
import ResponsayCore
import AppKit

/// Main-window shell: warm sidebar (Claude Design Scheme B) + feature content.
/// Dictation is NOT a nav item — it lives in the global hotkey + capsule.
struct MainWindowView: View {
    enum Section: String, CaseIterable, Identifiable {
        // 385 — 模型/改写/外观 moved to Settings; the main window is "看 + 用" only.
        // 快捷键 also lives in Settings. 主面板 (Overview) leads the sidebar.
        // 415 — 技能(法律)管理屏搬进设置「技能库」.
        // 识别词典 搬到「设置›输入」自己的家(用户常待设置、极少开本窗);主窗回归纯「看+用」。
        case overview, history
        var id: String { rawValue }
        var title: String {
            switch self {
            case .overview: "主面板"
            case .history: "历史"
            }
        }
        var icon: String {
            switch self {
            case .overview: "square.grid.2x2"
            case .history: "clock.arrow.circlepath"
            }
        }
        var subtitle: String {
            switch self {
            case .overview: "今天与最近 7 天的听写概览"
            case .history: "本机保存 · 默认 30 天后自动清理"
            }
        }
    }

    @State private var selection: Section = .overview
    @Environment(AppearanceStore.self) private var appearanceStore
    /// 254/255 — first-open prompt when no LLM provider is configured.
    /// Session-scoped dismissal: "稍后" hides it until the next app launch.
    @State private var setupPromptDismissed = false
    @State private var showSetupPrompt = false
    @State private var setupPromptNonce = 0

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 232)
            Rectangle().fill(appearanceStore.palette.hair).frame(width: 1)
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 920, minHeight: 620)
        .background(appearanceStore.palette.bg)
        .tint(appearanceStore.palette.accent)
        // Smoke/design-review hook (311): `responsay://open-main?screen=<raw>`
        // jumps straight to a sidebar section for screenshot regression runs.
        .onReceive(NotificationCenter.default.publisher(for: .init("OpenMainSection"))) { note in
            if let raw = note.object as? String, let section = Section(rawValue: raw) {
                selection = section
            }
        }
        .task(id: setupPromptNonce) {
            let summary = await Task.detached(priority: .utility) {
                ModelLaneDisplay.providerStatusSummary(from: ModelLaneDisplay().lanes())
            }.value
            guard !Task.isCancelled else { return }
            showSetupPrompt = ProviderSetupPromptCondition.shouldShow(
                summary: summary,
                dismissedThisSession: setupPromptDismissed)
        }
        .onReceive(NotificationCenter.default.publisher(for: .modelConfigurationDidChange)) { _ in
            setupPromptNonce &+= 1
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            setupPromptNonce &+= 1
        }
        .overlay {
            if showSetupPrompt {
                ProviderSetupPromptOverlay(
                    onLater: {
                        setupPromptDismissed = true
                        showSetupPrompt = false
                    },
                    onOpenSettings: {
                        setupPromptDismissed = true
                        showSetupPrompt = false
                        MacSettingsWindowController.shared.show()
                    })
            }
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: [appearanceStore.palette.accent, appearanceStore.palette.accentDeep],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 30, height: 30)
                    .overlay(Image(systemName: "waveform").foregroundStyle(.white).font(.system(size: 14, weight: .medium)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(AppBrand.displayName).font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(appearanceStore.palette.ink)
                    Text("听写 · 静默驻留").font(.system(size: 11)).foregroundStyle(appearanceStore.palette.ink3)
                }
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 14)

            Text("工作台")
                .font(.system(size: 10.5, weight: .bold)).foregroundStyle(appearanceStore.palette.ink3)
                .textCase(.uppercase).kerning(0.7)
                .padding(.horizontal, 18).padding(.bottom, 5)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(Section.allCases) { navItem($0) }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 0)

            Rectangle().fill(appearanceStore.palette.hair).frame(height: 1)
            HStack {
                Text("v" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")).font(SettingsTheme.mono).foregroundStyle(appearanceStore.palette.ink3)
                Spacer()
                Button { MacSettingsWindowController.shared.show() } label: {
                    Image(systemName: "gearshape").font(.system(size: 14))
                }
                .buttonStyle(.plain).foregroundStyle(appearanceStore.palette.ink2).help("设置")
            }
            .padding(.horizontal, 16).padding(.vertical, 11)
        }
        .background(SettingsTheme.sidebar)
    }

    private func navItem(_ s: Section) -> some View {
        let isOn = selection == s
        return Button {
            selection = s
        } label: {
            HStack(spacing: 11) {
                Image(systemName: s.icon)
                    .font(.system(size: 15))
                    .foregroundStyle(isOn ? appearanceStore.palette.accent : appearanceStore.palette.ink3)
                    .frame(width: 18)
                Text(s.title)
                    .font(.system(size: 13.5))
                    .fontWeight(isOn ? .medium : .regular)
                    .foregroundStyle(isOn ? appearanceStore.palette.ink : appearanceStore.palette.ink2)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8).padding(.horizontal, 11)
            .background(RoundedRectangle(cornerRadius: 9).fill(isOn ? appearanceStore.palette.card : Color.clear))
            .overlay(alignment: .leading) {
                if isOn {
                    RoundedRectangle(cornerRadius: 2).fill(appearanceStore.palette.accent)
                        .frame(width: 3).padding(.vertical, 7)
                }
            }
            .shadow(color: isOn ? .black.opacity(0.05) : .clear, radius: 1, y: 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        switch selection {
        case .overview:
            OverviewScreen()
        case .history:
            HistoryScreen()
        }
    }

}
