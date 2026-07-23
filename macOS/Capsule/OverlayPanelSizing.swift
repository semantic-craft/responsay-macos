import AppKit
import OSLog

/// #569 — the single size authority for SwiftUI-hosted overlay panels.
///
/// Crash family (1.3.22 revert chip · 1.4.9 correction-chip retitle · 1.4.14 layout loop):
/// AppKit's display-cycle loop breaker throws `NSGenericException` when a window is re-marked
/// "needs Update Constraints" past its per-cycle limit — uncaught inside the CA commit → SIGABRT.
/// The oscillation needs two size authorities fighting over one window: app code setting the
/// frame, and SwiftUI's hosting machinery steering the window toward its own ideal
/// (`updateAnimatedWindowSize`; with default `sizingOptions = .standardBounds` a hosting
/// view/controller rewrites the window's contentMinSize/contentMaxSize — Apple docs, verified
/// on-device; the controller setter forwards to its underlying NSHostingView, probed 7→0).
///
/// Defense in two layers: every host disables its sizing driver (`sizingOptions = []`), and
/// after app code decides a size the window is pinned (contentMinSize == contentMaxSize) so
/// the auto-layout window-size solution is unique — nothing left to oscillate.
///
/// Every pin/hide logs the `windowNumber`: AppKit DisplayCycle faults log `identifier NNNN`,
/// which IS the window number, so any future loop attributes to a named panel in one grep.
@MainActor
enum OverlayPanelSizing {
    private static let logger = Logger(
        subsystem: "com.semanticcraft.responsay.mac", category: "overlay-window")

    /// Measured fitting sizes can come back 0×0 (raw-NSHostingView quirk) — fall back per axis.
    static func resolved(_ measured: CGSize?, fallback: CGSize) -> CGSize {
        guard let measured else { return fallback }
        return CGSize(
            width: measured.width >= 1 ? measured.width : fallback.width,
            height: measured.height >= 1 ? measured.height : fallback.height)
    }

    /// Set the content size and freeze it. No-op (and no log) when already pinned at this size —
    /// callers re-run on every observed VM change, and repeat pins would churn layout for nothing.
    static func pin(_ panel: NSPanel, contentSize: CGSize, label: String) {
        guard !isPinned(panel, atContentSize: contentSize) else { return }
        unfreeze(panel)
        panel.setContentSize(contentSize)
        freeze(panel, atContentSize: contentSize, label: label)
    }

    /// Pin size and origin in one move, for panels that place their own frame
    /// (SelectionActionPanel keeps its top-left anchored while the menu grows down).
    static func pin(_ panel: NSPanel, frame: NSRect, label: String) {
        let contentSize = panel.contentRect(forFrameRect: frame).size
        guard panel.frame != frame || !isPinned(panel, atContentSize: contentSize) else { return }
        unfreeze(panel)
        panel.setFrame(frame, display: true)
        freeze(panel, atContentSize: contentSize, label: label)
    }

    /// Log-and-hide; the isVisible guard keeps the repeated hide* calls in the panels'
    /// `apply()` loops from spamming the log.
    static func hide(_ panel: NSPanel?, label: String) {
        guard let panel else { return }
        if panel.isVisible {
            logger.info("\(label, privacy: .public) window=\(panel.windowNumber) event=hide")
        }
        panel.orderOut(nil)
    }

    // MARK: - Freeze mechanics

    private static func isPinned(_ panel: NSPanel, atContentSize size: CGSize) -> Bool {
        panel.contentRect(forFrameRect: panel.frame).size == size
            && panel.contentMinSize == size
            && panel.contentMaxSize == size
    }

    private static func unfreeze(_ panel: NSPanel) {
        panel.contentMinSize = .zero
        panel.contentMaxSize = CGSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude)
    }

    private static func freeze(_ panel: NSPanel, atContentSize size: CGSize, label: String) {
        panel.contentMinSize = size
        panel.contentMaxSize = size
        logger.info("""
            \(label, privacy: .public) window=\(panel.windowNumber) \
            event=pin w=\(Int(size.width)) h=\(Int(size.height))
            """)
    }
}
