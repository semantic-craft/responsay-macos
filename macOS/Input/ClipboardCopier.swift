import AppKit
import OSLog
import ResponsayCore

/// Shared "trigger a copy, then read the pasteboard" with sentinel validation and pasteboard
/// backup/restore. The copy is triggered by a synthetic ⌘C by default; `MenuActionCopier` reuses
/// this same machinery but triggers the app's Copy *menu item* instead. Used by
/// `SelectionTextReader` as the clipboard fallback path(s).
@MainActor
enum ClipboardCopier {
    private static let log = Logger(subsystem: AppBrand.loggerSubsystem, category: "clipboard-copier")
    private static let signposter = OSSignposter(subsystem: AppBrand.loggerSubsystem, category: "clipboard-copier")

    static let pollingInterval: UInt64 = 30_000_000
    static let maxPollingIterations = 8
    static let targetActivationDelay: UInt64 = 80_000_000

    static func copy(
        from target: NSRunningApplication?,
        trigger: @MainActor () -> Bool = { postCommandC() }
    ) async -> String? {
        let state = signposter.beginInterval("clipboard-copy")
        defer { signposter.endInterval("clipboard-copy", state) }
        if let target {
            _ = target.activate()
            try? await Task.sleep(nanoseconds: targetActivationDelay)
        }

        let pasteboard = NSPasteboard.general
        let savedItems = cloneItems(pasteboard.pasteboardItems ?? [])

        let sentinel = "__responsay_sel_\(UUID().uuidString)__"
        pasteboard.clearContents()
        pasteboard.setString(sentinel, forType: .string)
        let sentinelChangeCount = pasteboard.changeCount

        guard trigger() else {
            log.warning("Copy trigger failed")
            // Nobody else wrote (only our sentinel) → safe to put the user's clipboard back.
            restoreIfUnchanged(items: savedItems, to: pasteboard, expecting: sentinelChangeCount)
            return nil
        }

        let (text, observedChangeCount) = await waitForChange(after: sentinelChangeCount, pasteboard: pasteboard)
        // CLIPBOARD-CLOBBER-001: restore the user's clipboard only if nothing wrote after the
        // value we read — a fresh user copy during the window must win (openless alignment).
        restoreIfUnchanged(items: savedItems, to: pasteboard, expecting: observedChangeCount)

        if text == nil || text == sentinel || text!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nil
        }
        return text
    }

    private static func waitForChange(after changeCount: Int, pasteboard: NSPasteboard) async -> (String?, Int) {
        for _ in 0..<maxPollingIterations {
            if pasteboard.changeCount != changeCount,
               let string = pasteboard.string(forType: .string) {
                return (string, pasteboard.changeCount)
            }
            try? await Task.sleep(nanoseconds: pollingInterval)
        }
        return (pasteboard.string(forType: .string), pasteboard.changeCount)
    }

    private static func restoreIfUnchanged(items: [NSPasteboardItem], to pasteboard: NSPasteboard, expecting changeCount: Int) {
        guard pasteboard.changeCount == changeCount else { return }
        restore(items: items, to: pasteboard)
    }

    private static func cloneItems(_ items: [NSPasteboardItem]) -> [NSPasteboardItem] {
        items.map { item in
            let clone = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    clone.setData(data, forType: type)
                } else if let string = item.string(forType: type) {
                    clone.setString(string, forType: type)
                }
            }
            return clone
        }
    }

    private static func restore(items: [NSPasteboardItem], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }

    private static func postCommandC() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }
        source.userData = SyntheticEventTag.userData  // so our Fn tap ignores its own output
        let cKeyCode: CGKeyCode = 8
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: false) else {
            return false
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}
