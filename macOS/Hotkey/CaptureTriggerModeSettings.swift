import Foundation

/// The capture trigger model is fixed to **tap-to-start / tap-to-stop** (Typeless-style):
/// tap a capture shortcut to begin recording, then tap any capture shortcut (e.g. Fn)
/// again to stop and process. The former hold-to-talk and double-tap modes were removed —
/// offering three trigger styles confused users. These accessors are kept (always toggle)
/// so existing call sites compile and any stale `triggerMode` / `doubleTapEnabled`
/// preference is ignored rather than silently re-enabling a retired mode.
enum CaptureTriggerModeSettings {
    enum Mode: String {
        case toggle
    }

    static func mode(defaults: UserDefaults = .standard) -> Mode {
        .toggle
    }

    static func isHoldToTalk(defaults: UserDefaults = .standard) -> Bool {
        false
    }

    static func isDoubleTap(defaults: UserDefaults = .standard) -> Bool {
        false
    }
}
