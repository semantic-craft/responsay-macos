import AppKit
import SwiftUI
import ResponsayCore

/// 截图取字 结果面板的窗口宿主。一个可成 key 的浮动窗口（可编辑 / 可拖动 / Esc 关闭），
/// 内容是 `SnapOCRPanelView`（暖纸卡片）。不同于胶囊系统的无边框 overlay：取字结果是「读 / 改 /
/// 复制」面，需要键盘焦点编辑文本，所以是普通 titled 窗口 + 透明标题栏（参照 anamra 的取字窗口）。
@MainActor
final class SnapOCRPanel {

    static let shared = SnapOCRPanel()

    private var window: NSWindow?

    private init() {}

    func show(result: OCRResult, image: CGImage) {
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        let view = SnapOCRPanelView(
            result: result, sourceImage: nsImage, cgImage: image,
            onClose: { [weak self] in self?.window?.close() })

        let window = self.window ?? makeWindow()
        let hostingView = NSHostingView(rootView: view)
        // #569: the window is the size authority (fixed 480×560) — don't let the hosting
        // view rewrite its min/max or resize it toward content.
        hostingView.sizingOptions = []
        window.contentView = hostingView
        self.window = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.level = .floating              // 停留在你刚取字的窗口之上，方便去别处粘贴
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(SettingsTheme.card)
        return window
    }
}
