import AppKit

/// The decision a raw `.flagsChanged` event maps to, extracted verbatim from
/// `FnHotkeyMonitor.handleFlags` so the routing rules are pure and testable.
///
/// The shell (`FnHotkeyMonitor`) keeps the side effects (driving the anchor state machines);
/// this enum only describes *what* should happen.
enum FnFlagsRoute: Equatable {
    /// Fn/Globe pressed (keyCode 63, `.function` set) — open the chord window.
    case anchorDown(ShortcutAnchor, NSEvent.ModifierFlags)
    /// Fn/Globe released (keyCode 63, `.function` cleared) — close the chord window.
    case anchorUp(ShortcutAnchor)
    /// Some other modifier changed while Fn is held — fold it into the pending chord.
    case modifiersChanged(NSEvent.ModifierFlags)
    /// Nothing to do (a modifier changed with no Fn held and no standalone match).
    case ignore
}

/// Pure flags-routing decision for the Fn/right-Option monitor.
///
/// Mirror of the original `FnHotkeyMonitor.handleFlags` branch order — moving the
/// logic out of the AppKit shell so the precedence (Fn key first, then right Option
/// only when Fn is NOT held, then the modifier-accumulation fall-through) is covered
/// by unit tests instead of only by real-key behavior.
enum FnFlagsRouter {
    /// macOS virtual keyCode for the physical Fn / 🌐 key.
    static let fnKeyCode: UInt16 = 63
    /// macOS virtual keyCode for the physical right Option key.
    static let rightOptionKeyCode: UInt16 = 61

    // MARK: - Routing

    /// Maps a `.flagsChanged` event (its keyCode + current modifier flags) to a route.
    ///
    /// Replicates the original branch order exactly:
    /// 1. Fn key (keyCode 63): `.function` set → Fn anchor down; cleared → Fn anchor up.
    /// 2. Right-Option keyCode (61) **and** Fn NOT held: start/end the right Option anchor.
    /// 3. Otherwise, if Fn or right Option is held, `.modifiersChanged`.
    /// 4. Otherwise, `.ignore`.
    static func route(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        rightOptionIsActive: Bool = false
    ) -> FnFlagsRoute {
        if keyCode == fnKeyCode {
            return modifierFlags.contains(.function)
                ? .anchorDown(.fn, modifierFlags)
                : .anchorUp(.fn)
        }

        if keyCode == rightOptionKeyCode, !modifierFlags.contains(.function) {
            if rightOptionIsActive {
                return .anchorUp(.rightOption)
            }
            // Solo Option only. A "Hyper key" remaps one physical key to ⌃⌥⌘⇧ at once; because
            // Option is among them, the bare-Option trigger used to misfire and open 任意提问.
            // Any Command/Control/Shift companion means this is a chord (Hyper or otherwise),
            // not a tap — so suppress the down. The matching release needs no guard: with no
            // recorded down, HotkeyDispatchTable's orphan-up suppression makes it a no-op.
            guard modifierFlags.contains(.option) else { return .anchorUp(.rightOption) }
            let companions: NSEvent.ModifierFlags = [.command, .control, .shift]
            return modifierFlags.isDisjoint(with: companions)
                ? .anchorDown(.rightOption, modifierFlags)
                : .ignore
        }

        if modifierFlags.contains(.function) || rightOptionIsActive {
            return .modifiersChanged(modifierFlags)
        }

        return .ignore
    }
}
