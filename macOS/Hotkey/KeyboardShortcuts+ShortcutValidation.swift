import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Shortcut {
    var isAllowedResponsayNormalShortcut: Bool {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)

        guard key != nil else {
            return false
        }

        if flags.contains(.function) {
            return false
        }

        return flags.contains(.command) || flags.contains(.control)
    }

    @MainActor
    var responsayDisplayString: String {
        description
    }
}
