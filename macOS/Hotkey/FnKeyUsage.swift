import AppKit

/// The macOS Globe / 🌐 (Fn) key carries a *system-level* action, set in
/// 系统设置 → 键盘 →「按下🌐键用于」(`com.apple.HIToolbox` key `AppleFnUsageType`):
///
///   0 不执行任何操作 · 1 更改输入法（带 Globe 键的 Mac 出厂默认）· 2 显示 Emoji · 3 开始听写
///
/// When it isn't `0`, the system consumes the Fn press (e.g. switches input source)
/// before our "轻点 Fn 开始说话" monitor can feel clean. We can't reliably override this
/// from userspace — Karabiner needs a HID driver, and writing the pref needs a restart —
/// so the app *detects* the conflict and guides the user to「不执行任何操作」, the path
/// mature dictation apps take. See `FnUsageGuidanceCard`.
enum FnKeyUsage {
    /// True when the Globe/Fn press is claimed by the system (anything but 0 / Do Nothing).
    /// Read from HIToolbox's domain via cfprefsd. An *unset* value is treated as "steals it"
    /// because Macs with a physical Globe key ship defaulting to 更改输入法.
    static var stealsFnPress: Bool {
        guard let raw = UserDefaults(suiteName: "com.apple.HIToolbox")?
            .object(forKey: "AppleFnUsageType") as? Int else { return true }
        return raw != 0
    }

    /// Open 系统设置 → 键盘 so the user can flip「按下🌐键用于」→「不执行任何操作」.
    /// (Ventura+ keyboard pane id; falls back to the Settings root if unavailable.)
    static func openKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
