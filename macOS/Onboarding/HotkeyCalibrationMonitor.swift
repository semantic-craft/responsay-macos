import AppKit

/// Local (app-focused) key monitor for the 设快捷键 calibration (spec §4.1). Detects a real press
/// of the chosen scheme's primary trigger while the onboarding window is key — a **local** monitor
/// sees the app's own event stream, so it needs no accessibility permission. Deliberately separate
/// from the production hotkey tap: a calibration glitch must never touch real capture.
@MainActor
final class HotkeyCalibrationMonitor {
    private var monitor: Any?

    func start(scheme: ShortcutScheme, onPress: @escaping @MainActor () -> Void) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            if Self.matches(type: event.type, modifiers: event.modifierFlags, scheme: scheme) {
                Task { @MainActor in onPress() }
            }
            return event   // never swallow the user's keystroke
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// Pure predicate (unit-tested): does this event represent a real press of the scheme's
    /// primary trigger? Fn scheme = the Fn (`.function`) flag; combo scheme = ⌃⌥⌘ held on a keyDown.
    nonisolated static func matches(type: NSEvent.EventType,
                                    modifiers: NSEvent.ModifierFlags,
                                    scheme: ShortcutScheme) -> Bool {
        switch scheme {
        case .fn:
            return type == .flagsChanged && modifiers.contains(.function)
        case .other:
            guard type == .keyDown else { return false }
            return modifiers.intersection(.deviceIndependentFlagsMask)
                .isSuperset(of: [.control, .option, .command])
        }
    }
}
