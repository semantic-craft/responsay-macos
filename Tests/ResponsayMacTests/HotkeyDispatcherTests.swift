import KeyboardShortcuts
import XCTest
@testable import ResponsayMac

/// `HotkeyDispatcher` owns hotkey registration + dispatch, extracted from `CaptureController`.
/// The pure `resolve*` seam is unit-testable without a live event tap or router: it maps a raw
/// edge (Fn chord / combo key) to the `HotkeyRouteCommand` the router would receive, or `nil`.
@MainActor
final class HotkeyDispatcherTests: XCTestCase {

    // A fresh store seeds the default Fn bindings (Fn → raw, Fn Shift → translate, Fn Space →
    // askAnything, Fn V → selectionMenu), so chords resolve out of the box with no stubbing.
    private func makeDispatcher(
        store: ShortcutSettingsStore
    ) -> (HotkeyDispatcher, () -> [HotkeyRouteCommand]) {
        var routed: [HotkeyRouteCommand] = []
        let dispatcher = HotkeyDispatcher(
            shortcutSettingsStore: store,
            route: { phase, action, trigger in
                routed.append(HotkeyRouteCommand(phase: phase, action: action, trigger: trigger))
            })
        return (dispatcher, { routed })
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "ResponsayMacTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    // MARK: - resolveFnChord

    func testResolveFnChordDownWithBoundActionReturnsDownCommand() {
        let store = ShortcutSettingsStore(defaults: makeDefaults())
        let (dispatcher, _) = makeDispatcher(store: store)

        let command = dispatcher.resolveFnChord(.down, chord: .fnOnly)

        XCTAssertEqual(command, HotkeyRouteCommand(phase: .down, action: .raw, trigger: .anchor(.fnOnly)))
    }

    func testResolveFnChordDownWithUnboundChordReturnsNil() {
        let store = ShortcutSettingsStore(defaults: makeDefaults())
        let (dispatcher, _) = makeDispatcher(store: store)

        // Fn+Control has no default binding → action resolves nil → no command.
        XCTAssertNil(dispatcher.resolveFnChord(.down, chord: .fnControl))
    }

    func testResolveFnChordMatchingUpReturnsUpCommandAfterDown() {
        let store = ShortcutSettingsStore(defaults: makeDefaults())
        let (dispatcher, _) = makeDispatcher(store: store)

        _ = dispatcher.resolveFnChord(.down, chord: .fnShift)
        let up = dispatcher.resolveFnChord(.up, chord: .fnShift)

        XCTAssertEqual(up, HotkeyRouteCommand(phase: .up, action: .translate, trigger: .anchor(.fnShift)))
    }

    func testResolveFnChordOrphanUpReturnsNil() {
        let store = ShortcutSettingsStore(defaults: makeDefaults())
        let (dispatcher, _) = makeDispatcher(store: store)

        // No prior down was recorded → the up edge is an orphan → suppressed.
        XCTAssertNil(dispatcher.resolveFnChord(.up, chord: .fnOnly))
    }

    func testResolveFnChordDownWithUnboundChordSuppressesFollowingUp() {
        let store = ShortcutSettingsStore(defaults: makeDefaults())
        let (dispatcher, _) = makeDispatcher(store: store)

        _ = dispatcher.resolveFnChord(.down, chord: .fnControl)   // nil action, records nothing
        XCTAssertNil(dispatcher.resolveFnChord(.up, chord: .fnControl))
    }

    // MARK: - resolveComboDown / resolveComboUp

    func testResolveComboDownMatchesRecordedComboAndReturnsDownCommand() {
        let store = ShortcutSettingsStore(defaults: makeDefaults())
        // Record ⌃⌥⌘Y on 语音输入 slot 0 so a combo key-down can match it.
        let comboShortcut = KeyboardShortcuts.Shortcut(.y, modifiers: [.control, .option, .command])
        KeyboardShortcuts.setShortcut(comboShortcut, for: NormalShortcutSlot(action: .raw, index: 0).name)
        defer { KeyboardShortcuts.setShortcut(nil, for: NormalShortcutSlot(action: .raw, index: 0).name) }
        let (dispatcher, _) = makeDispatcher(store: store)

        let command = dispatcher.resolveComboDown(
            keyCode: UInt16(comboShortcut.carbonKeyCode),
            modifierFlags: [.control, .option, .command])

        XCTAssertEqual(command?.phase, .down)
        XCTAssertEqual(command?.action, .raw)
    }

    func testResolveComboDownWithNoMatchReturnsNil() {
        let store = ShortcutSettingsStore(defaults: makeDefaults())
        let (dispatcher, _) = makeDispatcher(store: store)

        // A bare letter key-down with no recorded combo → no match.
        XCTAssertNil(dispatcher.resolveComboDown(keyCode: 16 /* y */, modifierFlags: []))
    }

    func testResolveComboUpAfterMatchingDownReturnsUpCommand() {
        let store = ShortcutSettingsStore(defaults: makeDefaults())
        let comboShortcut = KeyboardShortcuts.Shortcut(.y, modifiers: [.control, .option, .command])
        KeyboardShortcuts.setShortcut(comboShortcut, for: NormalShortcutSlot(action: .raw, index: 0).name)
        defer { KeyboardShortcuts.setShortcut(nil, for: NormalShortcutSlot(action: .raw, index: 0).name) }
        let (dispatcher, _) = makeDispatcher(store: store)
        let keyCode = UInt16(comboShortcut.carbonKeyCode)

        _ = dispatcher.resolveComboDown(keyCode: keyCode, modifierFlags: [.control, .option, .command])
        let up = dispatcher.resolveComboUp(keyCode: keyCode)

        XCTAssertEqual(up?.phase, .up)
        XCTAssertEqual(up?.action, .raw)
    }

    func testResolveComboUpWithoutPriorDownReturnsNil() {
        let store = ShortcutSettingsStore(defaults: makeDefaults())
        let (dispatcher, _) = makeDispatcher(store: store)

        // A key-up whose key-down we never swallowed (normal typing) must not be swallowed.
        XCTAssertNil(dispatcher.resolveComboUp(keyCode: 16 /* y */))
    }

    // MARK: - handleComboKeyDown/Up swallow-Bool contract

    func testHandleComboKeyDownReturnsTrueOnMatchAndFalseOtherwise() {
        let store = ShortcutSettingsStore(defaults: makeDefaults())
        let comboShortcut = KeyboardShortcuts.Shortcut(.y, modifiers: [.control, .option, .command])
        KeyboardShortcuts.setShortcut(comboShortcut, for: NormalShortcutSlot(action: .raw, index: 0).name)
        defer { KeyboardShortcuts.setShortcut(nil, for: NormalShortcutSlot(action: .raw, index: 0).name) }
        let (dispatcher, _) = makeDispatcher(store: store)
        let keyCode = UInt16(comboShortcut.carbonKeyCode)

        XCTAssertTrue(dispatcher.handleComboKeyDown(keyCode: keyCode, modifierFlags: [.control, .option, .command]))
        XCTAssertTrue(dispatcher.handleComboKeyUp(keyCode: keyCode))
        XCTAssertFalse(dispatcher.handleComboKeyDown(keyCode: 16, modifierFlags: []))
        XCTAssertFalse(dispatcher.handleComboKeyUp(keyCode: 16))
    }
}
