import AppKit

/// When auto-learn adds a corrected term to the recognition dictionary, show a small inline
/// toast just above the voice capsule's resting spot (bottom-centered) with a clickable 撤销 —
/// Typeless-style, not a giant corner banner and no OS notification. Auto-dismisses.
@MainActor
final class AutoLearnHotwordNotificationPresenter: NSObject {
    static let shared = AutoLearnHotwordNotificationPresenter()

    private var observer: NSObjectProtocol?
    private var toastPanel: NSPanel?
    private var toastTerm: String?
    private var toastDismissTask: Task<Void, Never>?
    private var toastShowTask: Task<Void, Never>?

    private static let toastSize = NSSize(width: 380, height: 46)
    /// Sits above the capsule (bottomCentered, margin 40, height 170 → top ≈ 210).
    private static let bottomMargin: CGFloat = 230

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .autoLearnHotwordDidAdd,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let term = note.userInfo?["term"] as? String
            Task { @MainActor in
                if let term { self?.showUndoToast(term: term) }
            }
        }
    }

    func undoAutoLearnedTerm(_ term: String) {
        UserDictionarySettingsStore().undoAuto(term)
    }

    // MARK: - Inline toast

    private func showUndoToast(term: String) {
        toastDismissTask?.cancel()
        toastTerm = term
        // #577: the toast joined the same display cycle as the insert-success chip swap —
        // one more window animation feeding the macOS 26 loop breaker (crash 8 forensics).
        // Showing it a beat later costs nothing and keeps that commit small.
        toastShowTask?.cancel()
        toastShowTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.presentToast(term: term)
        }
    }

    private func presentToast(term: String) {
        let panel = toastPanel ?? makeToastPanel()
        toastPanel = panel
        panel.contentView = makeToastView(term: term)
        positionToast(panel)
        panel.orderFrontRegardless()

        toastDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.toastPanel?.orderOut(nil)
            self?.toastTerm = nil
        }
    }

    private func makeToastPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.toastSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        return panel
    }

    private func makeToastView(term: String) -> NSView {
        let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.toastSize))
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 12
        blur.layer?.masksToBounds = true

        let label = NSTextField(labelWithString: "“\(term)” 已加入识别词典")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let button = NSButton(title: "撤销", target: self, action: #selector(undoToastAction))
        button.isBordered = false
        button.font = .systemFont(ofSize: 13, weight: .semibold)
        button.contentTintColor = NSColor(srgbRed: 0.82, green: 0.49, blue: 0.54, alpha: 1) // wine, legible on HUD
        button.setButtonType(.momentaryChange)

        let stack = NSStackView(views: [label, button])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -14),
            stack.centerYAnchor.constraint(equalTo: blur.centerYAnchor)
        ])
        button.setContentHuggingPriority(.required, for: .horizontal)
        return blur
    }

    private func positionToast(_ panel: NSPanel) {
        guard let frame = NSScreen.main?.visibleFrame else { return }
        panel.setFrameOrigin(PanelPlacement.bottomCentered(
            panelSize: Self.toastSize, visibleFrame: frame, margin: Self.bottomMargin))
    }

    @objc private func undoToastAction() {
        guard let toastTerm else { return }
        toastDismissTask?.cancel()
        undoAutoLearnedTerm(toastTerm)
        toastPanel?.orderOut(nil)
        self.toastTerm = nil
    }
}
