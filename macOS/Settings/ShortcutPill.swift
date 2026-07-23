import SwiftUI

struct ShortcutPill: View {
    let binding: ShortcutBinding
    @Bindable var store: ShortcutSettingsStore

    var body: some View {
        HStack(spacing: 5) {
            Text(displayText)
                .font(.caption)
                .monospaced()

            Button {
                store.remove(binding)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .imageScale(.small)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("删除快捷键")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary, in: Capsule())
        .opacity(binding.family == .fn && !anchorEnabled ? 0.45 : 1)
        .help(helpText)
    }

    private var displayText: String {
        switch binding.family {
        case .fn:
            return binding.fnChord?.displayString ?? "Fn"
        case .normal:
            guard let index = binding.normalSlotIndex else {
                return ""
            }
            let slot = NormalShortcutSlot(action: binding.action, index: index)
            return slot.name.shortcut?.responsayDisplayString ?? ""
        }
    }

    private var helpText: String {
        switch binding.family {
        case .fn:
            return "\(binding.fnChord?.anchor.displayString ?? "Fn") 快捷键"
        case .normal:
            return "普通快捷键"
        }
    }

    private var anchorEnabled: Bool {
        guard let anchor = binding.fnChord?.anchor else { return store.fnHotkeyEnabled }
        return store.isAnchorEnabled(anchor)
    }
}
