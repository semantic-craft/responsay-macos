import AppKit
import SwiftUI
import Observation
import ResponsayCore

/// Owns the two overlay windows and drives them off `vm.phase`:
/// - an indicator panel for `listening` · `thinking` · `error` whose visible
///   pill buttons can cancel / finish without activating the app,
/// - a **keyable** review card for `review`.
///
/// Observes the `@Observable` view model imperatively via `withObservationTracking`
/// (re-armed on each change) so the core VM needs no UI hook. Panel positioning
/// adapts to the visible frame of the screen under the mouse.
///
/// Window setup adapted from Kaze `RecordingOverlayWindow`
/// (https://github.com/fayazara/Kaze) — MIT License.
@MainActor
final class CapsulePanel {
    private let vm: QuickCaptureViewModel
    private var indicator: NSPanel?
    /// Keeps the indicator click-through (Typeless-style — content passes through) except while
    /// the pointer is over the pill, where mouse is re-enabled so ✕ / ✓ stay clickable. Event-driven
    /// (local + global mouse-move monitors): the old 80 ms polling timer left a window in which a
    /// fast move-and-click still fell through to the app underneath — the "second click needed" lag.
    private var hoverMonitors: [Any] = []
    private var review: ReviewPanel?
    /// Revert AI (P0b): the「↩ 原文」chip panel, shown bottom-center while `vm.revertableInsertion`
    /// is set. Clickable (not click-through) so its button works.
    private var revertChip: NSPanel?
    /// DISABLED (1.3.23 hotfix): rendering this chip raises an uncaught AppKit exception during the
    /// window layout / CA-commit cycle on macOS 26 → crash on every dictation. Kept off until the
    /// panel layout is fixed + verified on a real Mac. The vm still computes `revertableInsertion`
    /// (so its unit tests stay valid); only the rendering is gated here.
    private let revertChipEnabled = false
    /// 560: the「✓ 已按意图上屏 · 撤销」chip for Intent-aware inserts. Uses the proven-safe correction-chip
    /// pattern (a fresh hosting view per show, static content, no live retitle) so it avoids the
    /// CA-commit crash that keeps `revertChipEnabled` off. The undo LOGIC is unit-tested in Core; the
    /// real-host AX undo (delete / restore selection) is HITL-verified in #568.
    private var intentUndoChip: NSPanel?
    /// 518: the「✓ 已写入 · 纠正…」chip (clickable, non-activating) and the keyable correction
    /// mini panel it opens. New pure-SwiftUI views on the proven hosting pattern — real-machine
    /// HITL before release is the hard gate (issue 518).
    private var correctionChip: NSPanel?
    /// Title frozen into the visible chip (nil while hidden). While idle every observed VM change
    /// re-runs `apply` → `showCorrectionChip`; same title on a visible chip = nothing to relayout.
    private var correctionChipTitle: String?
    private var correctionPanel: ReviewPanel?

    init(vm: QuickCaptureViewModel) { self.vm = vm }

    /// Begin reflecting `vm.phase` in the overlay windows.
    func start() {
        apply(phase: vm.phase)
        observe()
    }

    // MARK: - Observation (re-armed each change)

    private func observe() {
        withObservationTracking {
            _ = vm.phase
            _ = vm.transcript
            _ = vm.isFinalizingTranscript
            _ = vm.errorMessage
            _ = vm.revertableInsertion
            _ = vm.correctionOffer
            _ = vm.correctionDraft
            _ = vm.intentInsertionTransaction
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.apply(phase: self.vm.phase)
                self.observe()  // re-arm for the next change
            }
        }
    }

    private func apply(phase: QuickCaptureViewModel.Phase) {
        switch phase {
        case .listening, .thinking, .error, .copied:
            hideReview()
            hideRevertChip()
            hideIntentUndoChip()
            hideCorrectionChip()
            hideCorrectionPanel()
            showIndicator()
        case .review:
            hideIndicator()
            hideRevertChip()
            hideIntentUndoChip()
            hideCorrectionChip()
            hideCorrectionPanel()
            showReview()
        case .idle:
            hideIndicator()
            hideReview()
            // Revert AI (P0b): the only thing the capsule shows while idle — a brief「↩ 原文」chip.
            if revertChipEnabled, vm.revertableInsertion != nil { showRevertChip() } else { hideRevertChip() }
            // #577: the SHOW half runs one runloop turn later, splitting the insert-success
            // transition across display cycles. Crash 8 proved the loop breaker fires inside
            // Apple's in-process input-method window (TUINSWindow, TextInputUI × SwiftUI on
            // macOS 26) when hides + chips + toast land in ONE commit — we can't pin a window
            // we don't own, but we can stop stacking invalidations into a single cycle. The
            // async closure re-reads the VM so a phase that moved on renders its own truth.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.vm.phase == .idle else { return }
                // 560: the Intent-aware safe-undo chip (delete verified / restore selection, never raw).
                if self.vm.intentInsertionTransaction != nil { self.showIntentUndoChip() } else { self.hideIntentUndoChip() }
                // 518: the「纠正…」chip after an insert; opening it swaps chip → keyable mini panel.
                if self.vm.correctionDraft != nil {
                    self.hideCorrectionChip()
                    self.showCorrectionPanel()
                } else {
                    self.hideCorrectionPanel()
                    if self.vm.correctionOffer != nil { self.showCorrectionChip() } else { self.hideCorrectionChip() }
                }
            }
        }
    }

    // MARK: - Indicator (non-activating, pointer actions on visible controls)

    private func showIndicator() {
        guard let screen = activeScreen else { return }
        let panel = indicator ?? makeIndicatorPanel()

        // NSHostingController — a raw NSHostingView silently paints nothing for these views (same
        // fix VoiceAssistantPanel uses). sizingOptions=[] so the animating waveform can't loop a
        // window-resize. The controller sizes the panel to the pill; we just center it.
        if panel.contentViewController == nil {
            let hc = NSHostingController(rootView: CapsuleView(vm: vm, notch: false))
            hc.sizingOptions = []
            panel.contentViewController = hc
        }
        // Measure the controller's view (this DOES report a real fittingSize, unlike a raw
        // NSHostingView) so the panel is sized exactly to the pill → exact horizontal centering.
        panel.contentViewController?.view.layoutSubtreeIfNeeded()
        let size = OverlayPanelSizing.resolved(
            panel.contentViewController?.view.fittingSize,
            fallback: CGSize(width: 204, height: 80))
        OverlayPanelSizing.pin(panel, contentSize: size, label: "capsule-indicator")
        // Margin lifts the pill clear above the Dock (the pill is centered in the window with the
        // shadow padding, so it needs a bit more than the bare edge margin).
        panel.setFrameOrigin(PanelPlacement.bottomCentered(panelSize: size, visibleFrame: screen.visibleFrame, margin: 6))
        panel.orderFrontRegardless()  // show without stealing focus
        startHoverTracking()
    }

    private func hideIndicator() {
        stopHoverTracking()
        OverlayPanelSizing.hide(indicator, label: "capsule-indicator")
    }

    // MARK: - Hover hit-test (click-through except over the pill)

    private func startHoverTracking() {
        syncMousePassthrough()   // the pointer may already sit over the pill when it appears
        guard hoverMonitors.isEmpty else { return }
        // Global sees moves while the panel is click-through (events route to the app behind);
        // local sees them once the panel is mouse-enabled. Together the pill turns clickable on
        // the very move that reaches it — no polling gap for a click to fall through.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged],
                                                          handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.syncMousePassthrough() }
        }) { hoverMonitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged],
                                                        handler: { [weak self] event in
            MainActor.assumeIsolated { self?.syncMousePassthrough() }
            return event
        }) { hoverMonitors.append(local) }
    }

    /// Inset to roughly the pill + its hover-label headroom (drop the transparent shadow padding)
    /// so only that zone catches the mouse; everywhere else stays click-through.
    private func syncMousePassthrough() {
        guard let panel = indicator, panel.isVisible else { return }
        let pill = panel.frame.insetBy(dx: 16, dy: 14)
        panel.ignoresMouseEvents = !pill.contains(NSEvent.mouseLocation)
    }

    private func stopHoverTracking() {
        hoverMonitors.forEach { NSEvent.removeMonitor($0) }
        hoverMonitors.removeAll()
        indicator?.ignoresMouseEvents = true
    }

    private func makeIndicatorPanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true   // click-through by default (Typeless-style); hover re-enables for ✕/✓
        panel.level = .screenSaver         // above everything incl. fullscreen, like Typeless (never occluded)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        indicator = panel
        return panel
    }

    private func positionIndicator(_ panel: NSPanel, size: CGSize, visibleFrame: CGRect) {
        panel.setFrameOrigin(PanelPlacement.bottomCentered(panelSize: size, visibleFrame: visibleFrame))
    }

    // MARK: - Revert chip (P0b — clickable, non-activating)

    private func showRevertChip() {
        guard let screen = activeScreen else { return }
        let panel = revertChip ?? makeRevertChipPanel()
        if panel.contentViewController == nil {
            let hc = NSHostingController(rootView: RevertChipView(vm: vm))
            hc.sizingOptions = []
            panel.contentViewController = hc
        }
        panel.contentViewController?.view.layoutSubtreeIfNeeded()
        let size = OverlayPanelSizing.resolved(
            panel.contentViewController?.view.fittingSize,
            fallback: CGSize(width: 220, height: 72))
        OverlayPanelSizing.pin(panel, contentSize: size, label: "revert-chip")
        panel.setFrameOrigin(PanelPlacement.bottomCentered(panelSize: size, visibleFrame: screen.visibleFrame, margin: 6))
        panel.orderFrontRegardless()  // show without stealing focus; its button still clicks
    }

    private func hideRevertChip() { OverlayPanelSizing.hide(revertChip, label: "revert-chip") }

    // MARK: - Intent-aware safe-undo chip (560 — clickable, non-activating, static content)

    private func showIntentUndoChip() {
        guard let screen = activeScreen else { return }
        let panel = intentUndoChip ?? makeIntentUndoChipPanel()
        // Fresh hosting view each show + static content (correction-chip pattern) → no live
        // constraint churn, so it stays clear of the CA-commit crash.
        if panel.isVisible { return }
        let hc = NSHostingController(rootView: IntentUndoChipView(vm: vm))
        hc.sizingOptions = []
        panel.contentViewController = hc
        hc.view.layoutSubtreeIfNeeded()
        let size = OverlayPanelSizing.resolved(
            hc.view.fittingSize, fallback: CGSize(width: 240, height: 72))
        OverlayPanelSizing.pin(panel, contentSize: size, label: "intent-undo-chip")
        panel.setFrameOrigin(PanelPlacement.bottomCentered(panelSize: size, visibleFrame: screen.visibleFrame, margin: 6))
        panel.orderFrontRegardless()  // show without stealing focus; its button still clicks
        // #574: every display-cycle crash so far struck within ~70ms of this moment —
        // snapshot the full window map so the fault's `identifier` resolves to a name.
        // #577: off the hot commit — the snapshot itself must not add cycle pressure.
        DispatchQueue.main.async { WindowInventoryDiag.log(moment: "intent-insert") }
    }

    private func hideIntentUndoChip() { OverlayPanelSizing.hide(intentUndoChip, label: "intent-undo-chip") }

    private func makeIntentUndoChipPanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false   // clickable so「撤销」receives the tap
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        intentUndoChip = panel
        return panel
    }

    private func makeRevertChipPanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Clickable (unlike the click-through indicator) so the「原文」button receives the tap.
        panel.ignoresMouseEvents = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        revertChip = panel
        return panel
    }

    // MARK: - 纠正并学习 (518 — chip + keyable mini panel)

    private func showCorrectionChip() {
        guard let offer = vm.correctionOffer else { return }
        let title = MishearCandidates.chipTitle(for: offer)
        let panel = correctionChip ?? makeCorrectionChipPanel()
        if panel.isVisible, correctionChipTitle == title { return }
        guard let screen = activeScreen else { return }
        // The chip's content must stay layout-static while on screen: the window size is frozen at
        // the measure below, and a later content-size change inside it re-marks Update Constraints
        // until AppKit's loop breaker throws NSGenericException (the 1.4.9 (117) crash — offer
        // expiry/replacement retitled the visible chip live). So the title is frozen into a fresh
        // hosting view per show, and a retitle passes through a hidden window.
        if panel.isVisible { panel.orderOut(nil) }
        let hc = NSHostingController(rootView: CorrectionChipView(vm: vm, title: title))
        hc.sizingOptions = []
        panel.contentViewController = hc
        correctionChipTitle = title
        hc.view.layoutSubtreeIfNeeded()
        let size = OverlayPanelSizing.resolved(
            hc.view.fittingSize, fallback: CGSize(width: 240, height: 72))
        OverlayPanelSizing.pin(panel, contentSize: size, label: "correction-chip")
        panel.setFrameOrigin(PanelPlacement.bottomCentered(panelSize: size, visibleFrame: screen.visibleFrame, margin: 6))
        panel.orderFrontRegardless()  // show without stealing focus; its button still clicks
    }

    private func hideCorrectionChip() {
        correctionChipTitle = nil
        OverlayPanelSizing.hide(correctionChip, label: "correction-chip")
    }

    private func makeCorrectionChipPanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Clickable (unlike the click-through indicator) so「纠正…」receives the tap.
        panel.ignoresMouseEvents = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        correctionChip = panel
        return panel
    }

    private func showCorrectionPanel() {
        guard let screen = activeScreen else { return }
        let panel = correctionPanel ?? makeCorrectionPanel()
        if panel.contentViewController == nil {
            let hc = NSHostingController(rootView: CorrectionLearnView(vm: vm))
            hc.sizingOptions = []
            panel.contentViewController = hc
        }
        panel.contentViewController?.view.layoutSubtreeIfNeeded()
        let size = OverlayPanelSizing.resolved(
            panel.contentViewController?.view.fittingSize,
            fallback: CGSize(width: 452, height: 320))
        OverlayPanelSizing.pin(panel, contentSize: size, label: "correction-panel")
        panel.setFrameOrigin(PanelPlacement.bottomCentered(panelSize: size, visibleFrame: screen.visibleFrame, margin: 60))
        panel.makeKeyAndOrderFront(nil)  // key (typing/Esc) but non-activating — ReviewPanel pattern
    }

    private func hideCorrectionPanel() { OverlayPanelSizing.hide(correctionPanel, label: "correction-panel") }

    private func makeCorrectionPanel() -> ReviewPanel {
        let panel = ReviewPanel(contentRect: .zero,
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        correctionPanel = panel
        return panel
    }

    // MARK: - Review (interactive, keyable)

    private func showReview() {
        guard let screen = activeScreen else { return }
        let panel = review ?? makeReviewPanel()
        // NSHostingController (raw NSHostingView stays empty for these views — see showIndicator).
        if panel.contentViewController == nil {
            let hc = NSHostingController(rootView: ReviewCardView(vm: vm))
            hc.sizingOptions = []
            panel.contentViewController = hc
        }
        let size = CGSize(width: 520, height: 560)
        OverlayPanelSizing.pin(panel, contentSize: size, label: "capsule-review")
        panel.setFrameOrigin(PanelPlacement.centered(panelSize: size, visibleFrame: screen.visibleFrame))
        panel.makeKeyAndOrderFront(nil)  // key (for Enter/Esc) but non-activating
    }

    private func hideReview() { OverlayPanelSizing.hide(review, label: "capsule-review") }

    private func makeReviewPanel() -> ReviewPanel {
        let panel = ReviewPanel(contentRect: .zero,
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        review = panel
        return panel
    }

    // MARK: - Geometry

    /// The screen under the mouse, falling back to the main screen.
    private var activeScreen: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens.first  // last-resort fallback (review #11)
    }

}
