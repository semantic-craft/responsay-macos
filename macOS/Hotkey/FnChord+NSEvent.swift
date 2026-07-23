import AppKit

extension FnChord {
    static func extractModifiers(
        from flags: NSEvent.ModifierFlags,
        anchor: ShortcutAnchor = .fn
    ) -> Set<FnModifier> {
        let deviceFlags = flags.intersection(.deviceIndependentFlagsMask)
        var modifiers = Set<FnModifier>()
        if deviceFlags.contains(.shift) { modifiers.insert(.shift) }
        if anchor != .rightOption, deviceFlags.contains(.option) { modifiers.insert(.option) }
        if deviceFlags.contains(.control) { modifiers.insert(.control) }
        if deviceFlags.contains(.command) { modifiers.insert(.command) }
        return modifiers
    }

    static func fromModifierFlags(
        _ flags: NSEvent.ModifierFlags,
        anchor: ShortcutAnchor = .fn
    ) -> FnChord {
        FnChord(anchor: anchor, modifiers: extractModifiers(from: flags, anchor: anchor), key: nil)
    }
}
