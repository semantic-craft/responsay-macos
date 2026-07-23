import AppKit
import ResponsayCore
import SwiftUI

/// The main browsable window (Claude Design 主窗口): sidebar nav + feature screens.
/// Distinct from the menu-bar capsule (dictation) and the Settings modal (config).
/// Opened from the menu bar or the `openApp` hotkey.
@MainActor
final class MainWindowController {
    static let shared = MainWindowController()

    private var window: NSWindow?

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let controller = NSHostingController(rootView: MainWindowView().environment(AppearanceStore.shared))
        // #569: with the default sizingOptions SwiftUI rewrites the window's min/max from
        // content (silently overriding the contentMinSize set below) and can resize the
        // window itself. The window is the size authority; the user resizes it.
        controller.sizingOptions = []
        let window = NSWindow(contentViewController: controller)
        window.title = AppBrand.displayName
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 1100, height: 760))
        window.contentMinSize = NSSize(width: 920, height: 620)
        window.center()
        return window
    }
}
