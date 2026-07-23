import ResponsayCore

/// A resolved hotkey routing decision — the phase, the action it maps to, and the
/// trigger that produced it. The shell hands this straight to `HotkeyActionRouter.handle`.
struct HotkeyRouteCommand: Equatable {
    let phase: HotkeyPhase
    let action: ShortcutAction
    let trigger: HotkeyTrigger
}

/// Pairs anchor chord key-down and key-up edges with their resolved action,
/// extracted from `CaptureController.handleFnChord`.
///
/// The down edge records the action it routed; the up edge only routes (and clears)
/// when a matching down was recorded. That `removeValue` guard is the orphan-up
/// suppression: a key-up with no prior recorded down (e.g. a stale gesture, or a
/// down whose action resolved to `nil`) produces no command.
struct HotkeyDispatchTable {
    private var anchorActions: [FnChord: ShortcutAction] = [:]

    /// Records `resolvedAction` for `chord` and returns the `.down` command.
    /// A `nil` action records nothing and returns `nil` (the shell logs the ignore).
    mutating func down(_ chord: FnChord, resolvedAction: ShortcutAction?) -> HotkeyRouteCommand? {
        guard let action = resolvedAction else { return nil }
        anchorActions[chord] = action
        return HotkeyRouteCommand(phase: .down, action: action, trigger: .anchor(chord))
    }

    /// Returns the `.up` command and clears the record — but only if a matching
    /// down was recorded (orphan-up suppression).
    mutating func up(_ chord: FnChord) -> HotkeyRouteCommand? {
        guard let action = anchorActions.removeValue(forKey: chord) else { return nil }
        return HotkeyRouteCommand(phase: .up, action: action, trigger: .anchor(chord))
    }
}
