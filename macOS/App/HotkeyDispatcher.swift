import AppKit
import KeyboardShortcuts
import OSLog
import ResponsayCore

/// Owns global hotkey **registration + dispatch** — the seam extracted from `CaptureController`.
///
/// Registration: normal (Carbon via `KeyboardShortcuts`) + Fn / 右 Option anchors and ⌃/⌘+letter
/// combos (native CGEventTap via `FnHotkeyMonitor`). Dispatch: a raw edge (Fn chord or combo key)
/// resolves to a `HotkeyRouteCommand`, which is handed to the injected `route` closure (production =
/// `HotkeyActionRouter.handle`). The router is NOT owned here — its handler closures reference the
/// coordinator's 6 sub-controllers, so the router stays in the coordinator and is reached via `route`.
///
/// The pure `resolve*` methods are the unit-testable core: no async, no live router — a raw edge in,
/// an optional command out. The side-effecting `handle*` wrappers call them, then dispatch.
@MainActor
final class HotkeyDispatcher {
    private let shortcutSettingsStore: ShortcutSettingsStore
    private let route: (HotkeyPhase, ShortcutAction, HotkeyTrigger) -> Void
    private let log: Logger

    private let normalHotkeyRegistrar = NormalHotkeyRegistrar()
    private let fnMonitor = FnHotkeyMonitor()
    // 划词菜单 is now summoned by Fn+V (CaptureSelectionController.showSelectionMenuFromHotkey).
    // The old hold-and-drag selection trigger was retired and its backup code deleted.
    private var dispatchTable = HotkeyDispatchTable()
    private var isSyncingFnMonitor = false

    /// Active combos keyed by the letter's keycode, so the matching key-up fires the same action and
    /// a key-up whose key-down we didn't swallow (normal typing) is never swallowed.
    private var activeComboKeys: [UInt16: (action: ShortcutAction, slot: NormalShortcutSlot)] = [:]

    init(
        shortcutSettingsStore: ShortcutSettingsStore = .shared,
        route: @escaping (HotkeyPhase, ShortcutAction, HotkeyTrigger) -> Void,
        log: Logger = Logger(subsystem: AppBrand.loggerSubsystem, category: "controller")
    ) {
        self.shortcutSettingsStore = shortcutSettingsStore
        self.route = route
        self.log = log
    }

    func configure() {
        normalHotkeyRegistrar.registerAllSlots { [weak self] phase, action, trigger in
            self?.route(phase, action, trigger)
        }

        fnMonitor.onDown = { [weak self] chord in
            self?.handleFnChord(.down, chord: chord)
        }

        fnMonitor.onUp = { [weak self] chord in
            self?.handleFnChord(.up, chord: chord)
        }

        // ⌃⌥⇧⌘+字母 combos fire through the event tap (Carbon RegisterEventHotKey proved unreliable
        // in-app; see ComboHotkeyMatcher). Anchors are tried first in FnHotkeyMonitor.
        fnMonitor.onComboKeyDown = { [weak self] keyCode, flags in
            self?.handleComboKeyDown(keyCode: keyCode, modifierFlags: flags) ?? false
        }
        fnMonitor.onComboKeyUp = { [weak self] keyCode in
            self?.handleComboKeyUp(keyCode: keyCode) ?? false
        }
    }

    /// Recorded combo bindings (any slot with a ⌃/⌘-bearing shortcut), rebuilt per press — cheap
    /// (~tens of lookups) and always current after the user re-records.
    private func comboBindings() -> [(action: ShortcutAction, slot: NormalShortcutSlot, shortcut: KeyboardShortcuts.Shortcut)] {
        var bindings: [(ShortcutAction, NormalShortcutSlot, KeyboardShortcuts.Shortcut)] = []
        for action in ShortcutAction.visibleInShortcutSettings {
            for slot in NormalShortcutSlot.slots(for: action) {
                if let shortcut = slot.name.shortcut {
                    bindings.append((action, slot, shortcut))
                }
            }
        }
        return bindings
    }

    // MARK: - Pure resolution (testable seam)

    /// Resolves a combo key-down to its `.down` command (and records it for the paired up), or `nil`
    /// when no recorded combo matches. Mutates `activeComboKeys`; no dispatch — sync + side-effect-free
    /// beyond the record, so tests can assert routing without a live tap/router.
    func resolveComboDown(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> HotkeyRouteCommand? {
        let pressedModifiers = ComboHotkeyMatcher.carbonModifiers(from: modifierFlags)
        guard let hit = comboBindings().first(where: {
            ComboHotkeyMatcher.matches(
                recordedKeyCode: $0.shortcut.carbonKeyCode,
                recordedModifiers: $0.shortcut.carbonModifiers,
                pressedKeyCode: Int(keyCode),
                pressedModifiers: pressedModifiers)
        }) else {
            return nil
        }
        activeComboKeys[keyCode] = (hit.action, hit.slot)
        return HotkeyRouteCommand(phase: .down, action: hit.action, trigger: .normal(hit.slot))
    }

    /// Resolves a combo key-up to its `.up` command and clears the record — but only if a matching
    /// key-down was swallowed (a key-up we never swallowed, i.e. normal typing, returns `nil`).
    func resolveComboUp(keyCode: UInt16) -> HotkeyRouteCommand? {
        guard let active = activeComboKeys.removeValue(forKey: keyCode) else {
            return nil
        }
        return HotkeyRouteCommand(phase: .up, action: active.action, trigger: .normal(active.slot))
    }

    /// Resolves an Fn / 右 Option chord edge to a command (or `nil` when unbound / orphan-up).
    /// Mutates `dispatchTable`; no dispatch.
    func resolveFnChord(_ phase: HotkeyPhase, chord: FnChord) -> HotkeyRouteCommand? {
        switch phase {
        case .down:
            let action = shortcutSettingsStore.action(for: chord)
            if let command = dispatchTable.down(chord, resolvedAction: action) {
                return command
            } else {
                log.debug("Anchor chord ignored: \(chord.id, privacy: .public)")
                return nil
            }
        case .up:
            return dispatchTable.up(chord)
        }
    }

    // MARK: - Side-effecting handlers (dispatch after resolving)

    func handleComboKeyDown(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        guard let command = resolveComboDown(keyCode: keyCode, modifierFlags: modifierFlags) else {
            return false
        }
        dispatchRouted(command)
        return true
    }

    func handleComboKeyUp(keyCode: UInt16) -> Bool {
        guard let command = resolveComboUp(keyCode: keyCode) else {
            return false
        }
        dispatchRouted(command)
        return true
    }

    func handleFnChord(_ phase: HotkeyPhase, chord: FnChord) {
        if let command = resolveFnChord(phase, chord: chord) {
            dispatchRouted(command)
        }
    }

    /// Run the resolved action on the next main-loop turn instead of inline.
    /// `handleFnChord` / `handleComboKeyDown` run *inside* the CGEventTap callback; opening a panel
    /// or starting capture there blocks the callback long enough for macOS to disable the tap (the
    /// "Fn stops working" bug). The swallow decision already happened upstream, so deferring the
    /// action is safe and keeps the callback fast. down/up arrive as separate key events, so the
    /// hops can't reorder within a single press.
    private func dispatchRouted(_ command: HotkeyRouteCommand) {
        Task { @MainActor in
            self.route(command.phase, command.action, command.trigger)
        }
    }

    func syncFnMonitor() {
        guard !isSyncingFnMonitor else { return }
        isSyncingFnMonitor = true
        defer { isSyncingFnMonitor = false }
        shortcutSettingsStore.refreshFromDefaults()
        if shortcutSettingsStore.fnHotkeyEnabled || shortcutSettingsStore.rightOptionHotkeyEnabled {
            fnMonitor.enable()
            refreshComboMatchTable()
        } else {
            fnMonitor.disable()
        }
    }

    /// Pushes the precomputed ⌃/⌘+letter swallow table to the tap thread, so the callback can eat a
    /// matched combo key-down without reaching the MainActor. Rebuilt on every sync — cheap and
    /// always current after the user re-records a shortcut.
    private func refreshComboMatchTable() {
        var table: [UInt16: [Int]] = [:]
        for (_, _, shortcut) in comboBindings() {
            guard let mods = ComboHotkeyMatcher.swallowModifiers(recordedModifiers: shortcut.carbonModifiers) else {
                continue
            }
            table[UInt16(shortcut.carbonKeyCode), default: []].append(mods)
        }
        fnMonitor.updateComboMatchTable(table)
    }
}
