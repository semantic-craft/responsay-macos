import AppKit
import ResponsayCore
import SwiftUI

@MainActor
final class MacSettingsWindowController {
    static let shared = MacSettingsWindowController()

    private var window: NSWindow?

    func show(section: SettingsSection? = nil) {
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if let section {
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .init("OpenSettingsSection"),
                    object: section.rawValue)
            }
        }
    }

    private func makeWindow() -> NSWindow {
        let controller = NSHostingController(rootView: SettingsView().environment(AppearanceStore.shared))
        // #569: with the default sizingOptions SwiftUI rewrites the window's min/max from
        // content (silently overriding the contentMinSize set below) and can resize the
        // window itself. The window is the size authority; the user resizes it.
        controller.sizingOptions = []
        let window = NSWindow(contentViewController: controller)
        window.title = "\(AppBrand.displayName) Settings"
        // Resizable with a roomy default so the two-pane layout isn't cramped
        // (matches the scale of OpenLess / Typeless settings).
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 1040, height: 720))
        window.contentMinSize = NSSize(width: 900, height: 600)
        window.center()
        return window
    }
}
