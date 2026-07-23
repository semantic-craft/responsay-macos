import AppKit
import SwiftUI
import Observation
import OSLog
import ResponsayCore

private let vaPanelLog = Logger(subsystem: AppBrand.loggerSubsystem, category: "va-panel")

@MainActor
final class VoiceAssistantPanel {
    private let vm: VoiceAssistantViewModel
    private var capsule: NSPanel?
    private var result: ReviewPanel?
    
    init(vm: VoiceAssistantViewModel) {
        self.vm = vm
    }
    
    func start() {
        apply(phase: vm.phase)
        observe()
    }
    
    /// Track ONLY phase + selectionContext — the things that decide which panel is shown. We must
    /// NOT track partialTranscript / level / messages.count here: those tick dozens of times a
    /// second (every spoken word, every waveform frame, every streamed token) and re-running the
    /// show/resize logic that often resizes the window in a loop → "needs another Update Constraints
    /// pass" → abort. The panel content itself updates fine: the hosted SwiftUI view observes `vm`
    /// directly and re-renders inside the fixed-size window without any window resize.
    private func observe() {
        withObservationTracking {
            _ = vm.phase
            _ = vm.selectionContext
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.apply(phase: self.vm.phase)
                self.observe()
            }
        }
    }
    
    private func apply(phase: VoiceAssistantViewModel.Phase) {
        guard let screen = activeScreen else {
            vaPanelLog.error("VA panel apply: activeScreen is NIL — nothing shown")
            return
        }
        vaPanelLog.info("VA panel apply: phase=\(String(describing: phase), privacy: .public) msgs=\(self.vm.messages.count, privacy: .public)")

        switch phase {
        case .listening, .thinking:
            hideResult()
            showCapsule(screen: screen)
        case .responding:
            hideCapsule()
            showResult(screen: screen)
        case .idle:
            // Show the panel when there's a conversation OR a freshly seeded
            // 任意提问 selection waiting for its first push-to-talk question.
            if !vm.messages.isEmpty || vm.selectionContext != nil {
                hideCapsule()
                showResult(screen: screen)
            } else {
                hideCapsule()
                hideResult()
            }
        }
    }
    
    // MARK: - Capsule

    private func showCapsule(screen: NSScreen) {
        let panel = capsule ?? makeCapsulePanel()

        // NSHostingController so SwiftUI paints reliably (a raw NSHostingView stuck at 0×0 stayed
        // empty). `sizingOptions = []` is REQUIRED: with the default the controller auto-resizes its
        // window to fit content, and while the waveform animates every frame it loops the
        // window-resize → "needs another Update Constraints pass" → abort. We size the panel ourselves.
        if panel.contentViewController == nil {
            let hc = NSHostingController(rootView: VoiceAssistantCapsuleView(vm: vm))
            hc.sizingOptions = []
            panel.contentViewController = hc
        }
        // FIXED size — never measured from the (changing) content, so the window never resizes while
        // listening (the waveform + partial text vary, but the pill is centered and the text is capped).
        // Wide enough for the unified capsule's fixed slots + shadow padding, and tall enough for the
        // floating "任意提问 · 倾听中…" label above the pill + the halo/shadow padding.
        let size = CGSize(width: 320, height: 170)
        OverlayPanelSizing.pin(panel, contentSize: size, label: "va-capsule")

        panel.setFrameOrigin(PanelPlacement.bottomCentered(panelSize: size, visibleFrame: screen.visibleFrame))
        panel.orderFrontRegardless()
    }

    private func hideCapsule() {
        OverlayPanelSizing.hide(capsule, label: "va-capsule")
    }
    
    private func makeCapsulePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        // Transparent again now that NSHostingController paints the content reliably — so the pill's
        // own rounded shape shows (no ugly opaque white rectangle behind it).
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        capsule = panel
        return panel
    }
    
    // MARK: - Result
    private func showResult(screen: NSScreen) {
        let panel = result ?? makeResultPanel()

        // NSHostingController so the card paints; `sizingOptions = []` stops it from auto-resizing the
        // window to the streaming answer (that resize loop aborts the app — see showCapsule).
        if panel.contentViewController == nil {
            let hc = NSHostingController(rootView: VoiceAssistantResultPanel(vm: vm, onClose: { [weak self] in
                self?.dismissResult()
            }))
            hc.sizingOptions = []
            panel.contentViewController = hc
        }
        // FIXED size; only set once so streaming never resizes it. The card view is
        // .frame(460×548) + 24pt shadow padding on each side → 508×596.
        let size = CGSize(width: 508, height: 596)
        OverlayPanelSizing.pin(panel, contentSize: size, label: "va-result")

        panel.setFrameOrigin(PanelPlacement.centered(panelSize: size, visibleFrame: screen.visibleFrame))
        panel.orderFrontRegardless()
    }

    private func hideResult() {
        OverlayPanelSizing.hide(result, label: "va-result")
    }

    /// The card's ✕ / Esc. Order the window out immediately, then reset the conversation.
    /// We hide directly because `clearConversation()` alone leaves `phase`/`selectionContext`
    /// unchanged for a plain 任意提问 (already `.idle`/`nil`), so the observer never re-applies
    /// and the window would otherwise stay up showing the empty state.
    private func dismissResult() {
        hideResult()
        vm.clearConversation()
    }
    
    private func makeResultPanel() -> ReviewPanel {
        let panel = ReviewPanel(contentRect: .zero,
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        // Transparent now that NSHostingController paints reliably — the card's own rounded background
        // + shadow show, instead of a big opaque white board.
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        result = panel
        return panel
    }
    
    private var activeScreen: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
}
