import AppKit
import OSLog
import ResponsayCore

@MainActor
final class SelectionTextReader {
    typealias AXReader = @MainActor (_ target: NSRunningApplication?) -> String?
    typealias ClipboardCopier = @MainActor (_ target: NSRunningApplication?) async -> String?

    private let axReader: AXReader
    private let menuActionCopier: ClipboardCopier
    private let clipboardCopier: ClipboardCopier
    private static let log = Logger(subsystem: AppBrand.loggerSubsystem, category: "selection-reader")
    private static let signposter = OSSignposter(subsystem: AppBrand.loggerSubsystem, category: "selection-reader")

    /// `menuActionCopier` is the middle tier — copy via the app's own Copy *menu item* (reliable
    /// in apps like WeChat where AX selected-text is empty and synthetic ⌘C is flaky). It defaults
    /// to a no-op so existing call sites/tests fall straight through to the ⌘C fallback.
    init(
        axReader: @escaping AXReader,
        menuActionCopier: @escaping ClipboardCopier = { _ in nil },
        clipboardCopier: @escaping ClipboardCopier
    ) {
        self.axReader = axReader
        self.menuActionCopier = menuActionCopier
        self.clipboardCopier = clipboardCopier
    }

    func readSelectedText(from target: NSRunningApplication?) async -> String? {
        let state = Self.signposter.beginInterval("readSelectedText")
        defer { Self.signposter.endInterval("readSelectedText", state) }

        if let text = axReader(target),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Self.log.info("AX succeeded; \(text.count) chars")
            return text
        }

        // WeChat & friends: AX exposes no selected text → press the app's Copy menu item via AX
        // (steadier than a synthetic keystroke) before falling back to ⌘C.
        if let text = await menuActionCopier(target),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Self.log.info("AX empty, menu-action copy succeeded; \(text.count) chars")
            return text
        }

        Self.log.info("AX + menu-action empty, Cmd+C fallback")
        return await clipboardCopier(target)
    }
}
