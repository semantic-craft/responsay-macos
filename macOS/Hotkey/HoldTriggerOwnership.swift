/// Single-owner gate for a push-to-talk hold session (HOTKEY-MODE-001).
///
/// Only the trigger that began a hold session may end it, so a different binding's
/// (or a stale gesture's) key-up can't cut a newer capture short. Extracted from
/// `CaptureSpeechController.activeHoldTrigger`: `acquire` on a successful hold start,
/// `release` on key-up — which only succeeds (and clears the owner) when the trigger
/// matches the current owner.
struct HoldTriggerOwnership {
    private(set) var owner: HotkeyTrigger?

    // MARK: - Ownership

    /// The given trigger now owns the active hold session.
    mutating func acquire(_ trigger: HotkeyTrigger) {
        owner = trigger
    }

    /// Releases the session if `trigger` is the current owner. Returns `true` and clears
    /// the owner when it matches; returns `false` (and leaves the owner intact) for a
    /// foreign or stale key-up, or when nothing owns the session.
    mutating func release(_ trigger: HotkeyTrigger) -> Bool {
        guard owner == trigger else { return false }
        owner = nil
        return true
    }
}
