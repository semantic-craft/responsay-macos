import SwiftUI

struct CurrentModelSelectionCard: View {
    let systemImage: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    @Binding var selection: String
    let options: [CurrentModelOption]
    var footer: LocalizedStringKey?
    var onSelect: (CurrentModelOption) -> Void = { _ in }

    var body: some View {
        WarmCard {
            CapabilityHeader(systemImage: systemImage, title: title, subtitle: subtitle)
            WarmDivider()
            VStack(alignment: .leading, spacing: 8) {
                ForEach(options) { option in
                    Button {
                        selection = option.id
                        onSelect(option)
                    } label: {
                        optionRow(option)
                    }
                    .buttonStyle(.plain)
                }
            }
            if let footer {
                Text(footer)
                    .font(SettingsTheme.footnote)
                    .foregroundStyle(SettingsTheme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
    }

    private func optionRow(_ option: CurrentModelOption) -> some View {
        let selected = option.id == selection
        return HStack(spacing: 11) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(selected ? SettingsTheme.wine : SettingsTheme.ink3)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(option.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SettingsTheme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(option.subtitle)
                    .font(SettingsTheme.footnote)
                    .foregroundStyle(SettingsTheme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 10)
            if selected {
                chip("当前使用", color: SettingsTheme.wine, fill: SettingsTheme.wineTint)
            }
            chip("\(option.badge)", color: option.badge == "本机" ? SettingsTheme.green : SettingsTheme.ink3,
                 fill: option.badge == "本机" ? SettingsTheme.greenBg : SettingsTheme.sunk)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? SettingsTheme.wineTint : SettingsTheme.field))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? SettingsTheme.wineLine : SettingsTheme.hair2,
                                                                lineWidth: 1))
    }

    private func chip(_ text: LocalizedStringKey, color: Color, fill: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(fill))
    }
}
