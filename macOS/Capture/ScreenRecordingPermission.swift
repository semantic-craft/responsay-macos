import AppKit
import CoreGraphics
import Foundation
import OSLog
import ScreenCaptureKit

// MARK: - 070 Snap & Translate · screen-recording permission
//
// Screen Recording is the 3rd permission (after Accessibility + Microphone). Interactive
// `screencapture -i` is driven by the system selector, which sidesteps in-process ScreenCaptureKit
// authorization — but we still preflight so a first-run Snap & Translate can guide the user when
// access is missing. The exact prompt/restart timing on a real Mac is a HITL verification tail
// (issue 070): on Sonoma+ a freshly granted capture permission can need an app restart.

enum ScreenRecordingPermission {
    /// True if screen capture is already authorized — no system prompt is shown.
    static var isAuthorized: Bool { CGPreflightScreenCaptureAccess() }

    /// Ask for screen-recording access (shows the system dialog the first time). Returns true if
    /// granted immediately; macOS frequently requires an app restart before it takes effect.
    ///
    /// `CGRequestScreenCaptureAccess()` alone doesn't reliably register this app with tccd (issue
    /// 514: confirmed via Console.app that tccd never receives a request from this process at
    /// all, for an app that otherwise never touches ScreenCaptureKit). `SCShareableContent` is
    /// the API tccd actually watches, so fire it too — purely for the registration side effect,
    /// its result is unused since the real capture still goes through `screencapture -i`.
    private static let log = Logger(subsystem: "com.semanticcraft.responsay.mac", category: "screen-recording-permission")

    @discardableResult
    static func request() -> Bool {
        let granted = CGRequestScreenCaptureAccess()
        SCShareableContent.getWithCompletionHandler { content, error in
            if let error {
                log.error("SCShareableContent registration error: \(error as NSError, privacy: .public)")
            } else {
                log.notice("SCShareableContent registration succeeded, displays=\(content?.displays.count ?? -1, privacy: .public)")
            }
        }
        return granted
    }

    @discardableResult
    static func requestFromUserAction() -> Bool {
        guard !isAuthorized else { return true }
        let granted = request() || isAuthorized
        if !granted { openSystemSettings() }
        return granted
    }

    static func openSystemSettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
