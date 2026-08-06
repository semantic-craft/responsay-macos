import AppKit
import ResponsayCore
import SwiftUI

/// The 朗读 reader — a real, resizable, floating window, deliberately not another overlay panel.
///
/// The screen-bottom capsule (`ReadAloudControlPanel`) is a non-activating click-through panel:
/// perfect for a remote control, useless for the one thing this window exists to do, which is
/// take a ⌘V of a long passage. Pasting needs key-window status, so the reader is an ordinary
/// `NSWindow` — which also buys ⌘` rotation, Mission Control, and moving it to another Space.
///
/// It floats above other apps (`.floating`) because you read while working in something else,
/// and it stays alive when closed so reopening returns to the same document.
@MainActor
final class ReadAloudReaderWindowController: NSWindowController, NSWindowDelegate {
    private let reader: ReadAloudDocumentReader

    init(reader: ReadAloudDocumentReader) {
        self.reader = reader
        let hosting = NSHostingController(
            rootView: ReadAloudReaderView(reader: reader).environment(AppearanceStore.shared))
        // The window is the size authority (#569): with default sizingOptions SwiftUI rewrites
        // min/max from content and can resize the window out from under the user.
        hosting.sizingOptions = []
        let window = NSWindow(contentViewController: hosting)
        window.title = "朗读"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.fullScreenAuxiliary, .managed]
        window.setContentSize(NSSize(width: 660, height: 470))
        window.contentMinSize = NSSize(width: 420, height: 300)
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Bring the reader forward. Activates the app: the point of opening it is to type or paste
    /// into it, which a background window cannot receive.
    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    var isOpen: Bool { window?.isVisible ?? false }

    /// Closing the reader is "put the window away", not "stop reading" — the capsule stays and
    /// keeps speaking, which is the whole point of it being the remote.
    func windowShouldClose(_ sender: NSWindow) -> Bool { true }
}
