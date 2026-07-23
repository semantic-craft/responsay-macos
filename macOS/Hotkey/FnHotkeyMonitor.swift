import AppKit
import OSLog
import ResponsayCore

/// Global monitor for the physical **Fn / 🌐** key and standalone right Option key.
///
/// The standard global-hotkey API (Carbon `RegisterEventHotKey`, used by `KeyboardShortcuts` and
/// by OpenTypeless's `tauri-plugin-global-shortcut`) cannot bind Fn — it requires a normal key.
/// Typeless reaches Fn through a native event monitor instead, which is what we do here: route
/// raw `.flagsChanged` / `.keyDown` / `.keyUp` events through a CGEventTap helper.
///
/// Two-stage detection (issue 270): Fn down opens a ~400ms `.keyDown` window. If a letter key
/// arrives during the window, a `FnChord` with that key is emitted (e.g. Fn+G). If no letter
/// arrives before Fn up or timeout, the modifier-only chord fires (existing behavior).
///
/// Requires Accessibility permission. NativeHotkeyEventTap owns the CGEventTap lifecycle and
/// swallows matched letter/Space key-down events so the trigger key never reaches the target app.
@MainActor
final class FnHotkeyMonitor {
    private let log = Logger(subsystem: AppBrand.loggerSubsystem, category: "fn-nsevent")
    var onDown: (@MainActor (FnChord) -> Void)?
    var onUp: (@MainActor (FnChord) -> Void)?
    /// A non-anchor key-down (e.g. Hyper+letter). Returns `true` if it matched a combo binding and
    /// should be swallowed — so Carbon never sees it and the letter never leaks into the document.
    var onComboKeyDown: (@MainActor (UInt16, NSEvent.ModifierFlags) -> Bool)?
    /// The matching key-up for a combo that was swallowed on the way down. Returns `true` to swallow.
    var onComboKeyUp: (@MainActor (UInt16) -> Bool)?
    private var eventTap: NativeHotkeyEventTap?

    private var fnStateMachine: FnChordStateMachine?
    private var rightOptionStateMachine: FnChordStateMachine?

    /// Tracks the right-Option key (keyCode 61) while the live recorder is capturing, so a captured
    /// letter can be classified as 右 Option + key (modifier flags alone can't tell left from right).
    private var recordingRightOptionDown = false
    private let recordingCoordinator = ShortcutRecordingCoordinator.shared
    /// macOS virtual keyCode for Escape — cancels an in-progress recording.
    private let escapeKeyCode: UInt16 = 53

    var isEnabled: Bool { eventTap != nil }

    func enable() {
        guard eventTap == nil else { return }

        fnStateMachine = FnChordStateMachine(
            anchor: .fn,
            onDown: { [weak self] chord in
                self?.log.info("Anchor down; chord \(chord.id, privacy: .public)")
                self?.onDown?(chord)
            },
            onUp: { [weak self] chord in
                self?.log.info("Anchor up; chord \(chord.id, privacy: .public)")
                self?.onUp?(chord)
            }
        )
        rightOptionStateMachine = FnChordStateMachine(
            anchor: .rightOption,
            onDown: { [weak self] chord in
                self?.log.info("Anchor down; chord \(chord.id, privacy: .public)")
                self?.onDown?(chord)
            },
            onUp: { [weak self] chord in
                self?.log.info("Anchor up; chord \(chord.id, privacy: .public)")
                self?.onUp?(chord)
            }
        )

        let tap = NativeHotkeyEventTap(log: log)
        tap.setActionHandler { [weak self] event in
            self?.handleActionEvent(event)
        }
        recordingCoordinator.onRecordingChange = { [weak tap] recording in
            tap?.setRecording(recording)
        }
        tap.setRecording(recordingCoordinator.isRecording)
        eventTap = tap
        if !tap.start() {
            log.warning("Fn chords disabled because native CGEventTap is unavailable")
        }
    }

    func disable() {
        eventTap?.stop()
        eventTap = nil
        recordingCoordinator.onRecordingChange = nil
        fnStateMachine = nil
        rightOptionStateMachine = nil
    }

    /// Forwards the precomputed combo swallow table to the tap thread (built by `CaptureController`).
    func updateComboMatchTable(_ table: [UInt16: [Int]]) {
        eventTap?.setComboMatchTable(table)
    }

    /// MainActor action side. Swallow is already decided on the tap thread (`FnSwallowDecider`);
    /// here we only advance the chord state machines / classify a recording, never decide swallow.
    private func handleActionEvent(_ event: NativeHotkeyEvent) {
        // While the settings recorder is capturing, classify the key instead of firing actions.
        if recordingCoordinator.isRecording {
            handleRecordingEvent(event)
            return
        }

        switch event {
        case let .flagsChanged(keyCode, modifierFlags):
            handleFlags(keyCode: keyCode, modifierFlags: modifierFlags)
        case let .keyDown(keyCode, modifierFlags):
            // A matched Fn / 右 Option chord claims the key first (as before); otherwise a combo
            // binding may. Swallow was already decided on the tap thread — this only fires actions.
            if letterKeyDown(keyCode: keyCode) { return }
            _ = onComboKeyDown?(keyCode, modifierFlags)
        case let .keyUp(keyCode):
            _ = onComboKeyUp?(keyCode)
        }
    }

    private func handleFlags(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) {
        // Pure routing decision lives in `FnFlagsRouter` (covered by unit tests); the
        // shell only performs the matching side effect. Branch order is preserved: Fn key
        // first, then the standalone right-Option trigger (only when Fn is NOT held, since
        // Fn + Option is the fnOption chord), then the modifier-accumulation fall-through —
        // Fn-then-Shift rarely lands on the same millisecond, so it must still form fn+shift
        // instead of collapsing to fn.
        switch FnFlagsRouter.route(
            keyCode: keyCode,
            modifierFlags: modifierFlags,
            rightOptionIsActive: rightOptionStateMachine?.isActive ?? false
        ) {
        case let .anchorDown(.fn, flags):
            fnStateMachine?.anchorDown(modifierFlags: flags)
        case let .anchorDown(.rightOption, flags):
            rightOptionStateMachine?.anchorDown(modifierFlags: flags)
        case .anchorUp(.fn):
            fnStateMachine?.anchorUp()
        case .anchorUp(.rightOption):
            rightOptionStateMachine?.anchorUp()
        case let .modifiersChanged(flags):
            fnStateMachine?.modifiersChanged(modifierFlags: flags)
            rightOptionStateMachine?.modifiersChanged(modifierFlags: flags)
        case .ignore:
            break
        }
    }

    private func letterKeyDown(keyCode: UInt16) -> Bool {
        let fnSwallowed = fnStateMachine?.letterKeyDown(keyCode: keyCode) ?? false
        let rightOptionSwallowed = rightOptionStateMachine?.letterKeyDown(keyCode: keyCode) ?? false
        return fnSwallowed || rightOptionSwallowed
    }

    /// Live-recorder capture: the tap thread already swallows every key while recording; here we only
    /// classify the key-down and report to the coordinator (or cancel on Escape).
    private func handleRecordingEvent(_ event: NativeHotkeyEvent) {
        switch event {
        case let .flagsChanged(keyCode, modifierFlags):
            if keyCode == FnFlagsRouter.rightOptionKeyCode {
                recordingRightOptionDown = modifierFlags.contains(.option)
            }
        case let .keyDown(keyCode, modifierFlags):
            defer { recordingRightOptionDown = false }
            if keyCode == escapeKeyCode {
                recordingCoordinator.cancel()
            } else if let captured = ShortcutRecordingClassifier.classify(
                keyCode: keyCode,
                modifierFlags: modifierFlags,
                rightOptionDown: recordingRightOptionDown) {
                recordingCoordinator.complete(captured)
            } else {
                recordingCoordinator.reject()
            }
        case .keyUp:
            break
        }
    }
}
