import CoreGraphics

/// Marks the synthetic key events this app posts — text insertion, ⌘V paste, ⌘C copy — so the Fn
/// `CGEventTap` recognises and passes through its *own* output instead of combo-matching or
/// swallowing it. Without this invariant, a user-defined ⌘/⌃ combo that happened to collide
/// with a key we synthesize (⌘C, ⌘V,
/// or the Unicode-payload key whose virtualKey is 0 == 'A') could be eaten by our own tap.
///
/// Apply with `source.userData = SyntheticEventTag.userData` on the source used to post; recognise
/// in the tap with `SyntheticEventTag.isOurs(event)`.
enum SyntheticEventTag {
    /// Stamped into `kCGEventSourceUserData` (CGEventField 42). Arbitrary non-zero sentinel,
    /// ASCII "RSAY" — a hardware event carries userData 0, so a real keypress never matches.
    static let userData: Int64 = 0x5253_4159

    /// True when `event` was posted by this app (carries our source user-data tag).
    static func isOurs(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == userData
    }
}
