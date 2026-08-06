import AppKit
import SwiftUI
import Observation
import ResponsayCore

/// Bottom-centered floating control for selection 朗读 — 暂停/继续 + 停止.
///
/// Mirrors `CapsulePanel`'s indicator: a non-activating, borderless `NSPanel` at
/// `.screenSaver` level, click-through except while the pointer is over the pill (so the
/// buttons stay clickable without stealing focus). Observes the `@Observable`
/// `ReadAloudController` and shows while a read is preparing/playing/paused, hides when idle.
@MainActor
final class ReadAloudControlPanel {
    private let reader: ReadAloudDocumentReader
    private let onOpenReader: () -> Void
    private var panel: NSPanel?
    private var hoverTimer: Timer?

    init(reader: ReadAloudDocumentReader, onOpenReader: @escaping () -> Void) {
        self.reader = reader
        self.onOpenReader = onOpenReader
    }

    /// Begin reflecting the controller's activity. Call once.
    func start() {
        apply()
        observe()
    }

    private func observe() {
        withObservationTracking {
            _ = reader.isActive
            _ = reader.phase
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.apply()
                self.observe()  // re-arm
            }
        }
    }

    private func apply() {
        if reader.isActive { show() } else { hide() }
    }

    private func show() {
        guard let screen = activeScreen else { return }
        let panel = panel ?? makePanel()
        if panel.contentViewController == nil {
            // NSHostingController (a raw NSHostingView paints nothing here — same fix CapsulePanel uses).
            let hc = NSHostingController(
                rootView: ReadAloudControlView(reader: reader, onOpenReader: onOpenReader))
            hc.sizingOptions = []
            panel.contentViewController = hc
        }
        panel.contentViewController?.view.layoutSubtreeIfNeeded()
        let size = OverlayPanelSizing.resolved(
            panel.contentViewController?.view.fittingSize,
            fallback: CGSize(width: 260, height: 76))
        OverlayPanelSizing.pin(panel, contentSize: size, label: "read-aloud")
        panel.setFrameOrigin(PanelPlacement.bottomCentered(
            panelSize: size, visibleFrame: screen.visibleFrame, margin: 6))
        panel.orderFrontRegardless()  // show without stealing focus
        startHoverTracking()
    }

    private func hide() {
        stopHoverTracking()
        OverlayPanelSizing.hide(panel, label: "read-aloud")
    }

    private func startHoverTracking() {
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel, panel.isVisible else { return }
                let pill = panel.frame.insetBy(dx: 16, dy: 14)
                panel.ignoresMouseEvents = !pill.contains(NSEvent.mouseLocation)
            }
        }
    }

    private func stopHoverTracking() {
        hoverTimer?.invalidate()
        hoverTimer = nil
        panel?.ignoresMouseEvents = true
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true   // click-through by default; hover re-enables for the buttons
        p.level = .screenSaver
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel = p
        return p
    }

    private var activeScreen: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
}
