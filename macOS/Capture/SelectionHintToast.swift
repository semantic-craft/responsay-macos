import AppKit

/// A small floating toast for selection actions whose follow-up the user can't see happen —
/// e.g. 来源核验 opens a no-param search page (知网 专业检索) and copies the 检索式 to the
/// clipboard for a manual paste. Floats above the just-opened browser (`.floating` +
/// `.nonactivatingPanel` + `orderFrontRegardless`) and auto-dismisses. Not an OS notification
/// (the app intentionally ships without 通知 permission).
///
/// ponytail: a standalone ~50-line toast rather than generalizing AutoLearnHotwordNotificationPresenter —
/// that one is coupled to the 撤销 flow + capsule placement; reuse it only if a third caller appears.
@MainActor
final class SelectionHintToast {
    static let shared = SelectionHintToast()

    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?
    private static let size = NSSize(width: 360, height: 44)

    /// Show `message` near `point` (defaults to the cursor, where the verify menu popped),
    /// replacing any toast already on screen. Auto-dismisses after 5s.
    func show(_ message: String, at point: NSPoint = NSEvent.mouseLocation) {
        dismissTask?.cancel()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = makeView(message)
        position(panel, near: point)
        panel.orderFrontRegardless()

        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.panel?.orderOut(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        return panel
    }

    private func makeView(_ message: String) -> NSView {
        let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.size))
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 12
        blur.layer?.masksToBounds = true

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -16),
            label.centerYAnchor.constraint(equalTo: blur.centerYAnchor),
        ])
        return blur
    }

    private func position(_ panel: NSPanel, near point: NSPoint) {
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        guard let vf = screen?.visibleFrame else { panel.setFrameOrigin(point); return }
        var origin = NSPoint(x: point.x - Self.size.width / 2, y: point.y - Self.size.height - 12)
        origin.x = min(max(origin.x, vf.minX + 8), vf.maxX - Self.size.width - 8)
        origin.y = min(max(origin.y, vf.minY + 8), vf.maxY - Self.size.height - 8)
        panel.setFrameOrigin(origin)
    }
}
