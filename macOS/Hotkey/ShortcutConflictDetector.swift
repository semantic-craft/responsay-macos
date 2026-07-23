import KeyboardShortcuts

@MainActor
struct ShortcutConflictDetector {
    func normalConflict(
        shortcut: KeyboardShortcuts.Shortcut,
        excluding excludedSlot: NormalShortcutSlot
    ) -> ShortcutAction? {
        for action in ShortcutAction.visibleInShortcutSettings {
            for slot in NormalShortcutSlot.slots(for: action) where slot != excludedSlot {
                if slot.name.shortcut == shortcut {
                    return action
                }
            }
        }

        return nil
    }

    func fnConflict(
        chord: FnChord,
        bindings: [ShortcutBinding],
        excluding bindingID: ShortcutBinding.ID? = nil
    ) -> ShortcutAction? {
        bindings.first {
            $0.id != bindingID
                && $0.isEnabled
                && $0.family == .fn
                && $0.fnChord == chord
        }?.action
    }

    func anchorConflict(
        chord: FnChord,
        bindings: [ShortcutBinding],
        excluding bindingID: ShortcutBinding.ID? = nil
    ) -> ShortcutAction? {
        fnConflict(chord: chord, bindings: bindings, excluding: bindingID)
    }
}
