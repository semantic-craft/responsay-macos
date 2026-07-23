import Foundation

enum HotkeyCalibrationState: Sendable, Equatable {
    case idle       // waiting for a real press
    case detected   // a real press was observed
    case confirmed  // user confirmed 是的，继续
}

/// Pure state machine for the 设快捷键 real keypress calibration (spec §4.1).
/// 是的，继续 is gated on an actually-observed key event, so the confirmation
/// can't happen before the OS really delivered the key to the app.
struct HotkeyCalibration: Sendable, Equatable {
    private(set) var state: HotkeyCalibrationState = .idle

    var canConfirm: Bool { state == .detected }
    var isConfirmed: Bool { state == .confirmed }

    /// A real key event was observed.
    mutating func keyPressed() {
        if state == .idle { state = .detected }
    }

    /// User clicked 是的，继续 — only valid after a real press.
    mutating func confirm() {
        if state == .detected { state = .confirmed }
    }

    /// 不行，换一个 / re-pick scheme.
    mutating func reset() {
        state = .idle
    }
}
