import AppKit

/// A borderless, non-activating panel that can still become **key** — so the
/// review card receives Enter/Esc/⌘C — without becoming **main** or activating
/// the app, keeping the user's target app frontmost for insertion.
///
/// Real-device caveat (spec §13.6): if becoming key still pulls focus off the
/// target app, fall back to a global `NSEvent` monitor and keep this non-key.
final class ReviewPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
