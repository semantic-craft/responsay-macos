import SwiftUI

struct SettingsToggleRow: View {
    @Environment(AppearanceStore.self) private var appearanceStore

    let title: LocalizedStringKey
    let desc: LocalizedStringKey?
    let binding: Binding<Bool>

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(appearanceStore.palette.ink)
                if let desc {
                    Text(desc).font(SettingsTheme.footnote).foregroundStyle(appearanceStore.palette.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: binding).labelsHidden().toggleStyle(.switch)
        }
        .padding(.vertical, 4)   // breathe — rows were flush; toward the spacious settings language
    }
}
