#if DEBUG
import AppKit
import SwiftUI

/// DEBUG-only floating window hosting `DiagnosticsPanelView` (issue 200). Always-on-top,
/// non-activating (so it doesn't steal focus while you drive 朗读/听写 in another app),
/// toggled from the menu bar. Mirrors `MacSettingsWindowController`. Not in release.
@MainActor
final class DiagnosticsWindowController {
    static let shared = DiagnosticsWindowController()

    private var panel: NSPanel?

    /// Show if hidden, hide if visible (menu-bar toggle).
    func toggle() {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
        } else {
            let panel = panel ?? makePanel()
            self.panel = panel
            panel.orderFrontRegardless()
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 440),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.title = String(localized: "诊断 · 语音栈")
        let controller = NSHostingController(rootView: DiagnosticsPanelView().environment(AppearanceStore.shared))
        controller.sizingOptions = []   // #569: the panel keeps its own 380×440; user resizes it
        panel.contentViewController = controller
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.center()
        return panel
    }
}
#endif
