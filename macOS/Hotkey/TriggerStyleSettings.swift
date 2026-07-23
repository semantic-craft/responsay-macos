import Foundation

/// How a voice-capture function is triggered from its hotkey:
/// - `.tap`  — toggle: press to start, press again to stop (good for long free dictation).
/// - `.hold` — push-to-talk: hold to record, release to get the result (good for a bounded
///   "say one phrase, get it back" transform like 地道外文).
public enum TriggerStyle: String, Sendable {
    case tap
    case hold
}

/// Gesture classifier mode for voice-capture releases.
/// - `both`     — tap and hold both live, told apart by press duration.
/// - `tapOnly`  — toggle only: a release never stops (only the next tap does).
/// - `holdOnly` — push-to-talk only: a release always stops, regardless of duration.
///
/// Ordinary Fn / right Option voice actions now resolve to `.tapOnly`. `.holdOnly` is reserved for
/// selection interaction controllers that inject it directly.
public enum TriggerGesture: String, Sendable {
    case both
    case tapOnly
    case holdOnly
}

/// Legacy resolver for voice trigger style. The old per-action setting key is left readable for
/// migration/tests, but runtime voice hotkeys always use tap-to-start/tap-to-stop. Selection
/// interaction is the only hold-to-submit route, and it passes `.holdOnly` directly.
enum TriggerStyleSettings {
    static func key(for action: ShortcutAction) -> String {
        "triggerStyle.\(action.rawValue)"
    }

    /// Legacy 2-value storage defaults to tap. Runtime capture no longer uses this as a mode
    /// switch; see `gesture(for:defaults:)`.
    static func defaultStyle(for _: ShortcutAction) -> TriggerStyle {
        .tap
    }

    static func style(for action: ShortcutAction, defaults: UserDefaults = .standard) -> TriggerStyle {
        if let raw = defaults.string(forKey: key(for: action)),
           let style = TriggerStyle(rawValue: raw) {
            return style
        }
        return defaultStyle(for: action)
    }

    static func setStyle(_ style: TriggerStyle, for action: ShortcutAction, defaults: UserDefaults = .standard) {
        defaults.set(style.rawValue, forKey: key(for: action))
    }

    // MARK: - Runtime gesture mode

    /// Ordinary voice hotkeys are tap-only. Hold-only is injected by selection interaction.
    static func defaultGesture(for _: ShortcutAction) -> TriggerGesture { .tapOnly }

    /// Persisted per-action gesture values are ignored for runtime capture. This deliberately
    /// collapses legacy `both` / `holdOnly` installs back to tap-only for Fn and right Option.
    static func gesture(fromRaw _: String?) -> TriggerGesture {
        .tapOnly
    }

    static func gesture(for _: ShortcutAction, defaults _: UserDefaults = .standard) -> TriggerGesture {
        .tapOnly
    }

    static func setGesture(_ gesture: TriggerGesture, for action: ShortcutAction, defaults: UserDefaults = .standard) {
        defaults.set(gesture.rawValue, forKey: key(for: action))
    }
}
