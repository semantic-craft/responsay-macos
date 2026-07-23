import AppKit
import OSLog
import ResponsayCore

/// Self-relaunch after the user grants Screen Recording. macOS applies that
/// permission only to a freshly launched process (per-process TCC cache), so we
/// offer a one-click restart instead of leaving the user to quit/reopen by hand —
/// the friction the system's own in-process "Quit & Reopen" affordance papers over,
/// which we don't get because OCR capture shells out to `screencapture`.
@MainActor
enum AppRelaunch {
    private static let log = Logger(subsystem: "com.semanticcraft.responsay.mac", category: "relaunch")

    /// Spawn a detached watcher that reopens this bundle once we exit, then quit.
    static func relaunch() {
        let argv = RelaunchCommand.shell(pid: getpid(), bundlePath: Bundle.main.bundlePath)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: argv[0])
        process.arguments = Array(argv.dropFirst())
        do {
            try process.run()
            log.info("relaunch watcher spawned; terminating")
            NSApp.terminate(nil)
        } catch {
            // Couldn't spawn the relauncher — stay running and let the user quit /
            // reopen manually rather than stranding them in a half state.
            log.error("relaunch spawn failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Offer a one-click relaunch (or a jump to System Settings) when a Screen
    /// Recording–gated capture produced nothing because the permission isn't yet
    /// effective for this process. Modal; safe to call from a snap-OCR failure path.
    static func promptScreenRecordingRelaunch() {
        NSApp.activate(ignoringOtherApps: true)
        let needsAuthorization = !ScreenRecordingPermission.isAuthorized
        let alert = NSAlert()
        alert.messageText = needsAuthorization ? String(localized: "允许屏幕录制以启用截图翻译") : String(localized: "重启以启用截图翻译")
        alert.informativeText = String(localized: "请在 系统设置 › 隐私与安全性 › 屏幕录制 中开启 Responsay。")
            + String(localized: "开启后如果仍无法截图，再重启 Responsay。")
        alert.addButton(withTitle: needsAuthorization ? String(localized: "打开屏幕录制设置") : String(localized: "重启 Responsay"))
        alert.addButton(withTitle: needsAuthorization ? String(localized: "重启 Responsay") : String(localized: "打开屏幕录制设置"))
        alert.addButton(withTitle: String(localized: "取消"))               // .alertThirdButtonReturn
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if needsAuthorization {
                ScreenRecordingPermission.requestFromUserAction()
            } else {
                relaunch()
            }
        case .alertSecondButtonReturn:
            if needsAuthorization {
                relaunch()
            } else {
                ScreenRecordingPermission.requestFromUserAction()
            }
        default:
            break
        }
    }
}
