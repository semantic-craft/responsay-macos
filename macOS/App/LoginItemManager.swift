import ServiceManagement
import OSLog
import ResponsayCore

/// Single source of truth for the "登录时启动应用" login item.
///
/// The toggle's *displayed* state lives in `@AppStorage("launchAtLogin")` (a remembered
/// preference), but the OS truth is `SMAppService.mainApp.status`. The two drift apart every
/// time the bundle is replaced — i.e. every app update: macOS silently drops the
/// background-task registration, yet the stored pref still reads ON, so nothing ever
/// re-registers and "开机自启" looks set but never fires at login. `reconcileAtLaunch()`
/// closes that gap on every launch.
enum LoginItemManager {
    static let prefKey = "launchAtLogin"

    private static let log = Logger(subsystem: AppBrand.loggerSubsystem, category: "login-item")

    /// Flip the login item on/off. Throws so the caller can revert its toggle on failure.
    static func setEnabled(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() }
        else { try SMAppService.mainApp.unregister() }
    }

    /// Self-heal the drift between the stored pref and the real OS registration. Call once at launch.
    static func reconcileAtLaunch() {
        let defaults = UserDefaults.standard
        let wantsLaunch = defaults.bool(forKey: prefKey)
        let status = SMAppService.mainApp.status

        switch (wantsLaunch, status) {
        case (true, .enabled):
            break  // pref and OS agree — nothing to do
        case (true, _):
            // Pref says ON but macOS isn't launching us (registration dropped by an update,
            // or never approved). Re-register so the next login actually works.
            do {
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval {
                    // ponytail: macOS shows its own "added a login item" prompt and exposes the
                    // toggle in System Settings → Login Items; nothing more the app can do here.
                    log.notice("Login item re-registered but needs approval in System Settings → 登录项与扩展.")
                }
            } catch {
                log.error("Login item self-heal failed: \(error.localizedDescription, privacy: .public)")
            }
        case (false, .enabled):
            // User enabled it directly in System Settings — make the toggle tell the truth.
            defaults.set(true, forKey: prefKey)
        default:
            break
        }
    }
}
