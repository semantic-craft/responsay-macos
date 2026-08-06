import KeyboardShortcuts
import SwiftUI

/// The single shortcut entry: one row per function, each showing its current bindings (any family)
/// plus one live recorder. Press **Fn / 右 Option / Hyper + 字母数字** and it captures it — replacing
/// the old three cards (Fn / 右 Option / 组合键). Fn defaults ship pre-set; recording just adds more.
struct UnifiedShortcutSection: View {
    @Environment(AppearanceStore.self) private var appearanceStore
    @Bindable var store: ShortcutSettingsStore

    /// The action whose recorder is currently armed (nil = not recording).
    @State private var editingAction: ShortcutAction?
    @State private var errorMessage: String?
    private let coordinator = ShortcutRecordingCoordinator.shared

    /// User-facing features worth a hotkey. Internal/niche actions (确认插入 / 打开应用 / 打开设置 / 选区
    /// 子动作) are intentionally omitted — they only appear below if a binding already exists.
    private static let primaryActions: [ShortcutAction] = [
        .raw, .translate, .askAnything, .expressInEnglish,
        .selectionMenu, .readAloudSelection, .snapOCR, .snapTextOCR, .snapImageCopy,
    ]

    private var displayedActions: [ShortcutAction] {
        let extras = ShortcutAction.visibleInShortcutSettings.filter {
            !Self.primaryActions.contains($0) && !store.bindings(for: $0).isEmpty
        }
        return Self.primaryActions + extras
    }

    var body: some View {
        WarmCard {
            CapabilityHeader(
                systemImage: "keyboard",
                title: "快捷键",
                subtitle: "每个功能一行。点「录制」后按下即可：Fn + 字母数字、右 Option + 字母数字，或带 ⌘/⌃ 且至少两个修饰键的组合 + 字母数字（如 ⌘⇧S、⌘⌥K、Hyper）。其他组合不收。单独 Fn、Fn+Shift、右 Option 这类不带字母的键录不进去，点「预设」直接选。Fn 默认已配好，录制是再加一个。")
            WarmDivider()

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(displayedActions.enumerated()), id: \.element) { index, action in
                    if index != 0 { WarmDivider() }
                    row(for: action)
                }
            }

            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }

            Text("带 ⌘/⌃ 的组合是全局快捷键：按下时当前应用的同名快捷键会被法言接管，建议用 ⌘⇧ 或 Hyper 这类不常占用的组合。Hyper = ⌃⌥⇧⌘ 一起按（常由 Caps Lock 改键得到）。")
                .font(SettingsTheme.footnote).foregroundStyle(appearanceStore.palette.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
        // The event-tap monitor reports captures here; consume on the main actor.
        .onChange(of: coordinator.captured) { _, captured in
            guard let captured, let action = editingAction else { return }
            store(captured, for: action)
            coordinator.captured = nil
            editingAction = nil
        }
        .onChange(of: coordinator.rejectionCount) { _, _ in
            guard editingAction != nil else { return }
            errorMessage = "只支持 Fn / 右 Option / 带 ⌘ 或 ⌃ 且至少两个修饰键的组合 + 字母或数字。"
            editingAction = nil
        }
    }

    private func row(for action: ShortcutAction) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(action.title)
                    .font(SettingsTheme.bodyFont.weight(.semibold))
                    .foregroundStyle(appearanceStore.palette.ink)
                Text(action.subtitle)
                    .font(SettingsTheme.footnote)
                    .foregroundStyle(appearanceStore.palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minWidth: 240, maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                ForEach(store.bindings(for: action)) { binding in
                    ShortcutPill(binding: binding, store: store)
                }
                recorderButton(for: action)
                presetMenu(for: action)
            }
        }
        .padding(.vertical, 2)
    }

    private func recorderButton(for action: ShortcutAction) -> some View {
        let isRecording = editingAction == action && coordinator.isRecording
        return Button {
            errorMessage = nil
            if isRecording {
                coordinator.cancel()
                editingAction = nil
            } else {
                editingAction = action
                coordinator.begin()
            }
        } label: {
            Text(isRecording ? "请按下…（Esc 取消）" : "录制")
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isRecording ? SettingsTheme.wine.opacity(0.18) : Color(.quaternaryLabelColor).opacity(0.4),
                            in: Capsule())
                .foregroundStyle(isRecording ? SettingsTheme.wine : appearanceStore.palette.ink2)
        }
        .buttonStyle(.plain)
        .help("录制 \(action.title) 的快捷键")
        .accessibilityLabel("录制 \(action.title) 快捷键")
    }

    /// Adds the **modifier-only anchor chords** (单独 Fn、Fn+Shift、右 Option …) that the live
    /// recorder can't capture: a bare Fn press emits only `.flagsChanged`, never the `.keyDown`
    /// the recorder completes on, and a chord with no letter key isn't in the recorder whitelist.
    /// Without this, deleting a default like `Fn → 语音输入` was a one-way trap (no way to re-add).
    /// Reuses `FnChord.stageOneAllowed(for:)` — the existing "modifier-only chords a user can pick".
    private func presetMenu(for action: ShortcutAction) -> some View {
        Menu {
            ForEach(ShortcutAnchor.allCases) { anchor in
                Section(anchor.displayString) {
                    ForEach(FnChord.stageOneAllowed(for: anchor)) { chord in
                        Button(chord.displayString) { addPreset(chord, for: action) }
                    }
                }
            }
        } label: {
            Text("预设")
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color(.quaternaryLabelColor).opacity(0.4), in: Capsule())
                .foregroundStyle(appearanceStore.palette.ink2)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("添加单独 Fn、Fn+Shift、右 Option 这类无法用「录制」捕捉的快捷键")
        .accessibilityLabel("为「\(action.title)」从预设添加快捷键")
    }

    /// Mirrors the `.anchorKey` branch of `store(_:for:)`: a recorded anchor shortcut must be live,
    /// and conflicts surface the same message as the recorder path.
    private func addPreset(_ chord: FnChord, for action: ShortcutAction) {
        errorMessage = nil
        do {
            try store.addFnBinding(action: action, chord: chord)
            store.setAnchorEnabled(true, anchor: chord.anchor)
        } catch ShortcutSettingsError.conflict(let existing) {
            errorMessage = "这个快捷键已经给了「\(existing.title)」。"
        } catch {
            errorMessage = "这个快捷键加不了。"
        }
    }

    private func store(_ shortcut: RecordedShortcut, for action: ShortcutAction) {
        switch shortcut {
        case let .anchorKey(anchor, keyCode):
            guard let key = FnKey.from(keyCode: keyCode) else { return }
            do {
                try store.addFnBinding(action: action, chord: FnChord(anchor: anchor, modifiers: [], key: key))
                store.setAnchorEnabled(true, anchor: anchor)  // a recorded anchor shortcut must be live
                errorMessage = nil
            } catch ShortcutSettingsError.conflict(let existing) {
                errorMessage = "这个快捷键已经给了「\(existing.title)」。"
            } catch {
                errorMessage = "这个快捷键加不了。"
            }
        case let .combo(keyCode, carbonModifiers):
            guard let slot = store.firstEmptyNormalSlot(for: action) else {
                errorMessage = "「\(action.title)」的组合键已满（最多 3 个）。"
                return
            }
            KeyboardShortcuts.setShortcut(
                KeyboardShortcuts.Shortcut(carbonKeyCode: Int(keyCode), carbonModifiers: carbonModifiers),
                for: slot.name)
            store.normalShortcutDidChange()
            errorMessage = nil
        }
    }
}
