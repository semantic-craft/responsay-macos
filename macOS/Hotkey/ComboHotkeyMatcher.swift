import AppKit
import Carbon.HIToolbox

/// Matches a recorded ⌃⌥⇧⌘-style ("Hyper") combo against a pressed key, for firing combos through
/// the native CGEventTap (`NativeHotkeyEventTap`) instead of Carbon `RegisterEventHotKey`.
///
/// Why: the Carbon path that `KeyboardShortcuts` registers proved unreliable in-app (a recorded
/// Hyper+letter never fired on real hardware, while the same library works in sibling apps without
/// our event tap). The event tap that already powers Fn / 右 Option *does* receive these key-downs
/// reliably — so combos ride it too. The tap swallows a matched key-down, so Carbon never sees it
/// and can't double-fire.
///
/// Pure + testable: no KeyboardShortcuts / CGEvent types, just the carbon keycode + modifier ints.
enum ComboHotkeyMatcher {
    /// The four device-independent modifier bits a combo may use. Masks out caps-lock and the
    /// left/right-specific bits so a synthesized Hyper key still compares equal to the recording.
    static let modifierMask = cmdKey | shiftKey | optionKey | controlKey

    /// Carbon modifier bitmask from a key event's `NSEvent.ModifierFlags` (masked to the four above).
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int {
        var modifiers = 0
        if flags.contains(.command) { modifiers |= cmdKey }
        if flags.contains(.option) { modifiers |= optionKey }
        if flags.contains(.control) { modifiers |= controlKey }
        if flags.contains(.shift) { modifiers |= shiftKey }
        return modifiers
    }

    /// The masked recorded modifiers for the tap-thread swallow table, or `nil` if the recording
    /// isn't a valid combo (no ⌘/⌃). Lets `CaptureController` build the table without importing
    /// Carbon, and keeps the swallow check identical to `matches`.
    static func swallowModifiers(recordedModifiers: Int) -> Int? {
        let recorded = recordedModifiers & modifierMask
        guard recorded & (cmdKey | controlKey) != 0 else { return nil }
        return recorded
    }

    /// True when a recorded combo matches the pressed key. Requires Command or Control in the
    /// recording so plain typing (no modifiers) can never match and get swallowed.
    static func matches(
        recordedKeyCode: Int,
        recordedModifiers: Int,
        pressedKeyCode: Int,
        pressedModifiers: Int
    ) -> Bool {
        let recorded = recordedModifiers & modifierMask
        guard recorded & (cmdKey | controlKey) != 0 else { return false }
        return recordedKeyCode == pressedKeyCode && recorded == (pressedModifiers & modifierMask)
    }
}
