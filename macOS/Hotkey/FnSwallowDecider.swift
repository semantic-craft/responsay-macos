/// Pure, synchronous swallow decision for the CGEventTap callback.
///
/// Phase 2 moves the tap onto its own RunLoop thread, so the callback can no longer reach the
/// `@MainActor` `FnChordStateMachine` to decide whether to eat a keystroke. This type holds *only*
/// the state the callback itself owns — which chord window is open and which key-downs have been
/// swallowed — and answers one question: should this event be eaten so it never reaches the focused
/// app? No timers, no I/O, no actions live here, so it is deterministic and table-testable.
///
/// Window semantics mirror `FnChordStateMachine`: an anchor's chord window opens on anchor-down,
/// and closes on anchor-up, on the first swallowed letter, or when the 400ms timer fires (the owner
/// drives all three via `setFnWindow`/`setRightOptionWindow`). Swallowing only inside the open
/// window keeps the swallow decision in lock-step with the action side, so a key is never eaten
/// without a chord firing. See ADR-0035.
struct FnSwallowDecider {
    /// KeyCodes a chord swallows while a window is open — A–Z, 0–9, Space. Anything else
    /// (arrows, ⌫, function keys) passes through so Fn+arrow / Fn+⌫ still reach the system.
    let letterKeyCodes: Set<UInt16>

    private(set) var fnWindowOpen = false
    private(set) var rightOptionWindowOpen = false
    /// KeyCodes whose key-down we ate, so the matching key-up is eaten too (no stray key-up).
    private(set) var swallowedKeyDowns: Set<UInt16> = []

    init(letterKeyCodes: Set<UInt16> = FnSwallowDecider.defaultLetterKeyCodes) {
        self.letterKeyCodes = letterKeyCodes
    }

    // MARK: - Window state (driven by the callback / tap-thread timer)

    mutating func setFnWindow(open: Bool) {
        fnWindowOpen = open
    }

    mutating func setRightOptionWindow(open: Bool) {
        rightOptionWindowOpen = open
    }

    // MARK: - Decisions

    /// Returns `true` to swallow this key-down. `comboMatch` is the precomputed answer to
    /// "does this keyCode+modifiers hit a ⌃/⌘ combo binding?" — kept out of here so the locked
    /// combo table stays in the owner.
    mutating func keyDown(keyCode: UInt16, comboMatch: Bool) -> Bool {
        if (fnWindowOpen || rightOptionWindowOpen) && letterKeyCodes.contains(keyCode) {
            swallowedKeyDowns.insert(keyCode)
            // One letter per window — a chord fires once, then further letters pass through
            // (matches FnChordStateMachine leaving `.waitingForLetterKey` after the first match).
            fnWindowOpen = false
            rightOptionWindowOpen = false
            return true
        }
        if comboMatch {
            swallowedKeyDowns.insert(keyCode)
            return true
        }
        return false
    }

    /// Returns `true` to swallow this key-up — only if its key-down was swallowed.
    mutating func keyUp(keyCode: UInt16) -> Bool {
        swallowedKeyDowns.remove(keyCode) != nil
    }

    // MARK: - Defaults

    /// A–Z, 0–9, Space keyCodes, mirroring `FnKey.keyCodeToDisplay`.
    static let defaultLetterKeyCodes: Set<UInt16> = [
        0, 11, 8, 2, 14, 3, 5, 4, 34, 38, 40, 37, 46, 45,
        31, 35, 12, 15, 1, 17, 32, 9, 13, 7, 16, 6,            // A–Z
        18, 19, 20, 21, 22, 23, 26, 28, 25, 29,               // 0–9
        49,                                                    // Space
    ]
}
