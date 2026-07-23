import SwiftUI

/// Card-based building blocks introduced by the domains settings redesign
/// (Claude Design handoff `responsay-settings.html`). They sit alongside the
/// existing `WarmCard` / `CapabilityHeader` family in `SettingsComponents`.

// MARK: - Sidebar domain accent

/// A user-facing settings domain. Drives the sidebar group dot + active-item
/// accent (法律 = wine, 英语 = teal, 系统 = warm brown). 输入 / 引擎 stay neutral.
enum SettingsDomain {
    case legal, english, system

    var color: Color {
        switch self {
        case .legal: SettingsTheme.cLegal
        case .english: SettingsTheme.cEng
        case .system: SettingsTheme.cSys
        }
    }
}

// MARK: - Status bar (real-time engine state)

/// The sunk pill at the top of each 引擎 pane that shows which source is live
/// (`.status-bar`). Compose `StatusDot` + `Text` segments inside it.
struct SettingsStatusBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 9) { content }
            .font(SettingsTheme.footnote)
            .foregroundStyle(SettingsTheme.ink2)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: SettingsTheme.radiusSmall).fill(SettingsTheme.sunk))
            .overlay(RoundedRectangle(cornerRadius: SettingsTheme.radiusSmall).strokeBorder(SettingsTheme.hair2, lineWidth: 1))
    }
}

/// 8px state dot with a soft tinted halo (matches the CSS `box-shadow` ring).
struct StatusDot: View {
    enum State { case green, amber, gray }
    let state: State

    private var color: Color {
        switch state {
        case .green: SettingsTheme.green
        case .amber: SettingsTheme.amber
        case .gray: SettingsTheme.ink3
        }
    }
    private var halo: Color {
        switch state {
        case .green: SettingsTheme.greenBg
        case .amber: SettingsTheme.amberBg
        case .gray: .clear
        }
    }

    var body: some View {
        ZStack {
            Circle().fill(halo).frame(width: 14, height: 14)
            Circle().fill(color).frame(width: 8, height: 8)
        }
        .frame(width: 14, height: 14)
    }
}

// MARK: - Card header with domain accent + trailing slot

/// Like `CapabilityHeader` but tinted by the pane's domain accent (法律/英语/系统)
/// and with an arbitrary trailing slot (a toggle, a status chip…). Used by the
/// redrawn domain panes; engine panes keep the wine `CapabilityHeader`.
struct CardHeader<Trailing: View>: View {
    let systemImage: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    var accent: Color
    @ViewBuilder var trailing: Trailing

    init(systemImage: String, title: LocalizedStringKey, subtitle: LocalizedStringKey,
         accent: Color = SettingsTheme.wine, @ViewBuilder trailing: () -> Trailing) {
        self.systemImage = systemImage
        self.title = title
        self.subtitle = subtitle
        self.accent = accent
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(accent.opacity(0.15))
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(accent)
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(SettingsTheme.cardTitle).foregroundStyle(SettingsTheme.ink)
                Text(subtitle).font(SettingsTheme.footnote).foregroundStyle(SettingsTheme.ink2)
            }
            Spacer(minLength: 8)
            trailing
        }
    }
}

extension CardHeader where Trailing == EmptyView {
    init(systemImage: String, title: LocalizedStringKey, subtitle: LocalizedStringKey, accent: Color = SettingsTheme.wine) {
        self.init(systemImage: systemImage, title: title, subtitle: subtitle, accent: accent) { EmptyView() }
    }
}

// MARK: - Soon chip (reserved / coming-soon marker, never an error state)

struct SoonChip: View {
    var label: LocalizedStringKey = "即将推出"
    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(SettingsTheme.ink3)
            .padding(.horizontal, 9)
            .padding(.vertical, 2)
            .background(Capsule().fill(SettingsTheme.sunk))
            .overlay(Capsule().strokeBorder(SettingsTheme.hair, lineWidth: 1))
    }
}

// MARK: - Memory residency chip (在内存 / 未加载)

struct MemChip: View {
    let resident: Bool
    var residentLabel: LocalizedStringKey = "已在内存"
    var outLabel: LocalizedStringKey = "未加载"

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(resident ? SettingsTheme.green : SettingsTheme.ink3).frame(width: 6, height: 6)
            Text(resident ? residentLabel : outLabel)
        }
        .font(.system(size: 11.5, weight: .semibold))
        .foregroundStyle(resident ? SettingsTheme.green : SettingsTheme.ink3)
        .padding(.horizontal, 9)
        .padding(.vertical, 2)
        .background(Capsule().fill(resident ? SettingsTheme.greenBg : SettingsTheme.sunk))
    }
}

// MARK: - Warm disclosure (collapsible "高级" block)

/// Custom collapsible matching `.disclosure`: a field-tinted rounded container
/// with a clickable header (lead icon + title + rotating chevron) and a body
/// shown only when open. Defaults to collapsed so the common path stays clean.
struct WarmDisclosure<Content: View>: View {
    let systemImage: String
    let title: LocalizedStringKey
    var startsOpen: Bool = false
    @ViewBuilder var content: Content

    @State private var open: Bool

    init(systemImage: String, title: LocalizedStringKey, startsOpen: Bool = false,
         @ViewBuilder content: () -> Content) {
        self.systemImage = systemImage
        self.title = title
        self.startsOpen = startsOpen
        self.content = content()
        _open = State(initialValue: startsOpen)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { open.toggle() }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: systemImage)
                        .font(.system(size: 14))
                        .foregroundStyle(SettingsTheme.ink2)
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SettingsTheme.ink)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SettingsTheme.ink3)
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if open {
                VStack(alignment: .leading, spacing: 16) { content }
                    .padding(.horizontal, 14)
                    .padding(.top, 2)
                    .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 11).fill(SettingsTheme.field))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(SettingsTheme.hair, lineWidth: 1))
    }
}
