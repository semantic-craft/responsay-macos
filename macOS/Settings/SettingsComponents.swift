import SwiftUI
import AppKit
import Security

/// Reusable warm-paper building blocks for the redesigned settings panes
/// (Claude Design Scheme B). Visual tokens come from `SettingsTheme`.

// MARK: - Card

/// Ivory rounded "paper" card with hairline border + soft shadow.
struct WarmCard<Content: View>: View {
    var padding: CGFloat = SkinMetrics.cardPadding
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 20) { content }   // 16→20: roomier inter-row rhythm
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .warmCardSurface(shadow: .rest)   // 311: shared family chrome
    }
}

// MARK: - Capability header (icon tile + title + subtitle + badges)

struct CapabilityHeader: View {
    let systemImage: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    var searchCapable: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: SkinMetrics.radiusSmall).fill(SettingsTheme.wineTint)
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .medium))   // icon glyph — icon sizes stay literal
                    .foregroundStyle(SettingsTheme.wine)
            }
            .frame(width: SkinMetrics.iconTile, height: SkinMetrics.iconTile)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(SettingsTheme.cardTitle).foregroundStyle(SettingsTheme.ink)
                Text(subtitle).font(SettingsTheme.footnote).foregroundStyle(SettingsTheme.ink2)
            }
            Spacer(minLength: 8)
            if searchCapable { SearchBadge() }
        }
    }
}

/// `🔍 可联网检索` chip — marks providers whose API can call web search.
struct SearchBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
            Text("可联网检索")
        }
        .font(.system(size: SkinMetrics.fsCaption, weight: .semibold))
        .foregroundStyle(SettingsTheme.cEng)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(SettingsTheme.cEngBg))
        .help("该模型 API 可直接联网检索，供「来源核验 · URL 直查」复用")
    }
}

// MARK: - Labeled row (78px label + content, like the design's cap-grid)

struct LabeledRow<Content: View>: View {
    let label: LocalizedStringKey
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(label)
                .font(SettingsTheme.footnote)
                .foregroundStyle(SettingsTheme.ink2)
                .frame(width: 104, alignment: .leading)
            content
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Fields

/// A plain editable field in the warm field style (mono for URLs / model ids).
struct WarmField: View {
    let placeholder: LocalizedStringKey
    @Binding var text: String
    var mono: Bool = true

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(mono ? SettingsTheme.mono : SettingsTheme.bodyFont)
            .padding(.horizontal, 10)
            .frame(height: SkinMetrics.fieldHeight)
            .background(RoundedRectangle(cornerRadius: SkinMetrics.radiusSmall).fill(SettingsTheme.field))
            .overlay(RoundedRectangle(cornerRadius: SkinMetrics.radiusSmall).strokeBorder(SettingsTheme.fieldBorder, lineWidth: 1))
    }
}

/// Secret field with reveal (👁) + paste (📋) — the BYOK key input.
struct SecureKeyField: View {
    let placeholder: LocalizedStringKey
    @Binding var text: String
    @State private var revealed = false

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if revealed {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(SettingsTheme.mono)
            Button { revealed.toggle() } label: {
                Image(systemName: revealed ? "eye.slash" : "eye")
            }
            .buttonStyle(.plain)
            .foregroundStyle(SettingsTheme.ink3)
            .help(revealed ? "隐藏" : "显示")
            Button {
                if let pasted = NSPasteboard.general.string(forType: .string) {
                    text = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "clipboard")
                    Text("粘贴")
                }
                .font(.system(size: SkinMetrics.fsCaption))
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(Capsule().fill(SettingsTheme.wine.opacity(0.10)))
            }
            .buttonStyle(.plain)
            .foregroundStyle(SettingsTheme.wine)
            .help("从剪贴板粘贴 API Key")
        }
        .padding(.horizontal, 10)
        .frame(height: SkinMetrics.fieldHeight)
        .background(RoundedRectangle(cornerRadius: SkinMetrics.radiusSmall).fill(SettingsTheme.field))
        .overlay(RoundedRectangle(cornerRadius: SkinMetrics.radiusSmall).strokeBorder(SettingsTheme.fieldBorder, lineWidth: 1))
    }
}

/// A copyable hint chip (海外 / 套餐 端点).
struct CopyChip: View {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "doc.on.clipboard")
                Text(label)
            }
            .font(.system(size: SkinMetrics.fsCaption))
            .foregroundStyle(SettingsTheme.wine)
        }
        .buttonStyle(.plain)
        .help(value)
    }
}

/// ALL-CAPS group label (`.glabel`).
struct GroupLabel: View {
    let text: LocalizedStringKey
    var body: some View {
        Text(text)
            .font(SettingsTheme.groupLabel)
            .foregroundStyle(SettingsTheme.ink3)
            .textCase(.uppercase)
            .kerning(0.6)
    }
}

// MARK: - Hairline divider between card rows

struct WarmDivider: View {
    var body: some View {
        Rectangle().fill(SettingsTheme.hair2).frame(height: 1)
    }
}

// MARK: - Spacious settings language (Claude Design 设置 redesign)
//
// In-content page header + a generous label-left / control-right row, matching
// the Typeless-spacious settings spec (pane-head + .row). Panes compose these in
// a max-width column so the two-pane window breathes instead of feeling cramped.

/// In-content page header: Title + optional one-line subtitle, with bottom air.
struct SettingsPaneHeader: View {
    @Environment(AppearanceStore.self) private var appearanceStore
    let title: LocalizedStringKey
    var desc: LocalizedStringKey? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(SettingsTheme.paneTitle)
                .foregroundStyle(appearanceStore.palette.ink)
            if let desc {
                Text(desc)
                    .font(SettingsTheme.footnote)
                    .foregroundStyle(appearanceStore.palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, SkinMetrics.sp2)
    }
}

/// One settings line: left title (+ optional description), right control.
/// Roomy vertical padding so rows aren't flush — the core of the spacious feel.
struct SettingsRow<Control: View>: View {
    @Environment(AppearanceStore.self) private var appearanceStore
    let title: LocalizedStringKey
    var desc: LocalizedStringKey? = nil
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: SkinMetrics.sp4) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(SettingsTheme.bodyFont.weight(.medium))
                    .foregroundStyle(appearanceStore.palette.ink)
                if let desc {
                    Text(desc)
                        .font(SettingsTheme.footnote)
                        .foregroundStyle(appearanceStore.palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            control
        }
        .padding(.vertical, 6)
    }
}

/// Wraps pane content in a centered max-width column with generous margins —
/// the `.content`/`.pane` spec (页边距 sp6, 内容 max-width). Use as the root of
/// each spacious pane so every screen shares the same breathing room.
struct SettingsPaneColumn<Content: View>: View {
    @Environment(AppearanceStore.self) private var appearanceStore
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SkinMetrics.sp5) { content }
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, SkinMetrics.sp5)
                .padding(.vertical, SkinMetrics.sp6)
        }
        .background(appearanceStore.palette.bg)
    }
}

// MARK: - BYOK Keychain (generic, per-account)

/// Self-contained generic Keychain accessor for BYOK secrets, keyed by an
/// arbitrary account string (e.g. `byok.qwen`). Values never touch UserDefaults
/// or logs. Mirrors the existing per-provider store but works for any provider id.
enum BYOKKeychain {
    private static let service = "com.responsay.byok"

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return nil }
        return value
    }

    static func write(_ value: String, account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        guard !value.isEmpty else {
            SecItemDelete(base as CFDictionary)
            return
        }
        let data = Data(value.utf8)
        let status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}
