import AppKit
import ApplicationServices
import OSLog
import ResponsayCore

/// Electron/Chromium apps ship with their accessibility tree disabled and only build it when an
/// assistive client asks — until then the focused element reads as NoValue even with the cursor
/// blinking in an input box, so the editable-focus gate wrongly fires a copy pill
/// (ELECTRON-AX-OPAQUE-001; Claude Desktop / Codex / Cursor / Slack are all this class, and
/// half of `ForceInsertApps` exists to paper over it). Setting the Electron-documented
/// "AXManualAccessibility" attribute at capture start gives the renderer the few seconds of
/// speech to build the tree, so the stop-time gate — and every other AX read, 屏幕上下文
/// included — sees the real focused field. Non-Electron apps just reject the attribute with a
/// harmless error, so no per-app list is needed.
///
/// Real Chrome and the other Chromium/Gecko browsers are the same class for their **web content**:
/// their web tree stays hidden until an assistive client sets "AXEnhancedUserInterface", so a
/// dictation into any web `<input>`/`<textarea>` (Gemini / Google 搜索 / 豆瓣) wrongly fired a copy
/// pill (CHROME-WEB-AX-001). For the bundles in `BrowserBundleIDs.webAXTreeUnlock` we set that
/// attribute too — the switch Typeless uses (reverse-eng report §4.1/§11.3). Scoped to browsers
/// because "AXEnhancedUserInterface" can perturb layout in some non-browser AppKit apps.
/// ponytail: wired to the dictation path only; the tree build is async (~seconds), so an
/// utterance shorter than the build still falls back to `ForceInsertApps` / the chrome heuristic.
@MainActor
final class ElectronAXUnlock {
    private let log = Logger(subsystem: AppBrand.loggerSubsystem, category: "ax-unlock")
    private let isTrusted: () -> Bool
    private let setAttribute: (pid_t, String?) -> Void
    private var requestedPIDs: Set<pid_t> = []

    init(
        isTrusted: @escaping () -> Bool = { AccessibilityPermission.isTrusted },
        setAttribute: @escaping (pid_t, String?) -> Void = ElectronAXUnlock.setManualAccessibility
    ) {
        self.isTrusted = isTrusted
        self.setAttribute = setAttribute
    }

    func request(for app: NSRunningApplication?) {
        guard let app else { return }
        request(pid: app.processIdentifier, bundleID: app.bundleIdentifier)
    }

    /// Idempotent per app process: the attribute sticks for the app's lifetime, so one request
    /// per pid is enough; a relaunched app gets a fresh pid and a fresh request. Untrusted
    /// requests don't burn the pid — once 辅助功能 is granted, the same app still gets unlocked.
    func request(pid: pid_t, bundleID: String?) {
        guard isTrusted() else { return }
        guard requestedPIDs.insert(pid).inserted else { return }
        setAttribute(pid, bundleID)
        log.info("Requested AX tree unlock for \(bundleID ?? "unknown", privacy: .public)")
    }

    nonisolated private static func setManualAccessibility(pid: pid_t, bundleID: String?) {
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        // Chromium/Gecko browsers only build their web-content tree once an assistive client sets
        // this — without it every web field is invisible to the gate and fires a copy pill
        // (CHROME-WEB-AX-001). Scoped to `BrowserBundleIDs` since it can perturb non-browser apps.
        if BrowserBundleIDs.needsWebAXTreeUnlock(bundleID) {
            AXUIElementSetAttributeValue(axApp, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
    }
}
