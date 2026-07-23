import AppKit
import SwiftUI
import ResponsayCore

/// A floating, borderless panel hosting `SelectionActionMenu` near the cursor.
/// The menu draws its own warm-paper card, shadow and anchor triangle, so the panel
/// stays fully transparent and shadowless. It resizes as the menu expands (icon row →
/// smart row → dropdown), keeping the triangle's top edge anchored to the selection.
final class SelectionActionPanel: NSPanel {
    private var globalMonitor: Any?
    /// Screen-space top-left the menu grows down from (keeps the triangle put).
    private var menuTopLeft: CGPoint?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.level = .floating
        self.backgroundColor = .clear
        self.hasShadow = false                 // the SwiftUI menu draws its own soft shadow
        self.isOpaque = false
        self.acceptsMouseMovedEvents = true    // so the menu's hover highlights work
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.animationBehavior = .utilityWindow
    }

    func show(
        at point: CGPoint,
        text: String,
        items: [SelectionMenuItem],
        onPick: @escaping (SelectionAction, String) -> Void,
        onPickSkill: @escaping (String, String) -> Void,
        onCustomize: @escaping () -> Void
    ) {
        menuTopLeft = CGPoint(x: point.x + 10, y: point.y - 10)

        let view = SelectionActionMenu(
            items: items,
            onPick: { [weak self] action in self?.closePanel(); onPick(action, text) },
            onPickSkill: { [weak self] id in self?.closePanel(); onPickSkill(id, text) },
            onCustomize: { [weak self] in self?.closePanel(); onCustomize() },
            onClose: { [weak self] in self?.closePanel() },
            onLayoutChange: { [weak self] size in self?.resize(to: size) }
        )

        let hostingView = NSHostingView(rootView: view)
        // #569: default sizingOptions (.standardBounds) let SwiftUI rewrite this window's
        // min/max and steer its size — fighting `resize(to:)` below is exactly the layout
        // loop AppKit's breaker aborts on. The menu reports its size via onLayoutChange;
        // the panel is the only size authority.
        hostingView.sizingOptions = []
        self.contentView = hostingView
        hostingView.layout()
        resize(to: hostingView.fittingSize)
        self.orderFront(nil)
        setupDismissMonitor()
    }

    /// Fit the panel to the menu, keeping the top-left fixed so the menu grows
    /// downward (macOS y-up: lower the origin as the height grows).
    private func resize(to size: CGSize) {
        guard size.width > 1, size.height > 1, let top = menuTopLeft else { return }
        OverlayPanelSizing.pin(
            self,
            frame: NSRect(x: top.x, y: top.y - size.height, width: size.width, height: size.height),
            label: "selection-menu")
    }

    private func setupDismissMonitor() {
        if globalMonitor != nil { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePanel()
        }
    }

    private func closePanel() {
        OverlayPanelSizing.hide(self, label: "selection-menu")
        menuTopLeft = nil
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
    }
}
