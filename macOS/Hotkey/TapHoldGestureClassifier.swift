import Foundation

/// Pure decision logic for tap-only and injected hold-only voice triggers.
///
/// At the press edge we cannot yet tell a tap from a hold, so a key-down always *begins* a
/// capture session — unless one is already listening, in which case the press is a second tap
/// that stops it. The release edge classifies the gesture by how long the key was held: a
/// release at or past `threshold` is a push-to-talk hold (stop now); a shorter release is a
/// tap, which leaves the session listening (hands-free) to be stopped by the next tap.
///
/// The `.both` mode is kept as classifier support for old tests/sandboxes, but ordinary Fn /
/// right Option voice actions resolve to `.tapOnly`. Selection interaction injects `.holdOnly`.
///
/// Because tap behaviour is unchanged (a quick press still begins/toggles, a quick release is a
/// no-op), 方案 A is a strict superset of the old tap toggle: it only *adds* "held past the
/// threshold → release stops it".
enum TapHoldGesture: Equatable {
    /// Start a capture session on this press; the gesture is not yet known to be tap or hold.
    case begin
    /// A press while already listening — a second tap stops the hands-free session.
    case stopHandsFree
    /// A release at or past `threshold` — a push-to-talk hold ends, so stop the session.
    case stopPushToTalk
    /// Nothing to do: a short tap's release keeps the session listening (hands-free), or the
    /// release is foreign / stale (a different trigger, or none, owns the session).
    case ignore
}

enum TapHoldGestureClassifier {
    /// Press-duration boundary for `.both` mode. Ordinary runtime hotkeys do not use `.both`.
    static let defaultThreshold: TimeInterval = 0.25

    /// Press edge. `isListening` is true when a capture session is already active.
    static func onDown(isListening: Bool) -> TapHoldGesture {
        isListening ? .stopHandsFree : .begin
    }

    /// Release edge. `heldFor` is how long the key was held; `ownsSession` is true only when this
    /// trigger started the still-active session (HOTKEY-MODE-001, `HoldTriggerOwnership`). The
    /// per-function `gesture` override (issue 408) decides how the release is read:
    /// - `.both`: a release at or past `threshold` is a push-to-talk stop;
    ///   anything shorter keeps the session listening (the tap became hands-free).
    /// - `.tapOnly`: a release never stops — pure toggle, stopped only by the next tap's down.
    /// - `.holdOnly`: a release always stops — pure push-to-talk, regardless of duration.
    static func onUp(
        gesture: TriggerGesture = .both,
        heldFor duration: TimeInterval,
        threshold: TimeInterval = defaultThreshold,
        isListening: Bool,
        ownsSession: Bool
    ) -> TapHoldGesture {
        guard isListening, ownsSession else { return .ignore }
        switch gesture {
        case .tapOnly:  return .ignore
        case .holdOnly: return .stopPushToTalk
        case .both:     return duration >= threshold ? .stopPushToTalk : .ignore
        }
    }
}
