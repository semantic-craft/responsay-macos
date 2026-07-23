import AppKit

/// A shortcut captured by the live recorder, in one of the families the unified entry accepts:
/// **Fn + 字母数字**, **右 Option + 字母数字**, or any **⌘/⌃-bearing combo + 字母数字** (⌘⇧S, ⌘⌥K,
/// Hyper, …). Anything else is rejected.
enum RecordedShortcut: Equatable {
    /// Fn or 右 Option anchor + an alphanumeric key — stored as a `FnChord`, fired by the anchor engine.
    case anchorKey(anchor: ShortcutAnchor, keyCode: UInt16)
    /// A ⌘/⌃-bearing combo + alphanumeric key — stored in a normal slot, fired by `ComboHotkeyMatcher`
    /// via the event tap. `carbonModifiers` is the exact recorded modifier set (e.g. ⌘⇧ = 768).
    case combo(keyCode: UInt16, carbonModifiers: Int)
}

/// Pure classification of a recorded key press into a `RecordedShortcut` (or `nil` to reject).
/// Kept side-effect-free so the whitelist is unit-tested instead of only exercised by real keys.
enum ShortcutRecordingClassifier {
    /// `rightOptionDown` comes from the monitor tracking the right-Option key (keyCode 61), since the
    /// modifier flags alone can't tell left Option from right.
    static func classify(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        rightOptionDown: Bool
    ) -> RecordedShortcut? {
        // Only alphanumeric (and Space) keys are bindable — `FnKey.from` is exactly that table.
        guard FnKey.from(keyCode: keyCode) != nil else { return nil }

        let masked = modifierFlags.intersection(.deviceIndependentFlagsMask)

        if masked.contains(.function) {
            // Fn + key only — Fn plus another modifier is not in the whitelist.
            return masked.subtracting(.function).isEmpty ? .anchorKey(anchor: .fn, keyCode: keyCode) : nil
        }
        if rightOptionDown, masked == [.option] {
            return .anchorKey(anchor: .rightOption, keyCode: keyCode)
        }
        // A combo carrying ⌘ or ⌃ with **at least two modifiers** (⌘⇧S, ⌘⌥K, ⌃⌥M, Hyper, …). The
        // 2-modifier floor keeps a single ⌘+key (e.g. ⌘N) from being recorded and globally shadowing a
        // common app shortcut — these combos are intercepted system-wide, so 3+ keys is the safe floor.
        // Bare ⌥/⇧+key (no ⌘/⌃) is rejected too, so it can't shadow Option-typing or a capital letter.
        if masked.contains(.command) || masked.contains(.control) {
            let modifierCount = [.command, .control, .option, .shift].filter(masked.contains).count
            guard modifierCount >= 2 else { return nil }
            return .combo(keyCode: keyCode, carbonModifiers: ComboHotkeyMatcher.carbonModifiers(from: masked))
        }
        return nil
    }
}
