import AppKit
import Carbon
import ResponsayCore
import OSLog

/// Inserts idiomatic text into the frontmost app's focused field.
///
/// Strategy: first try synthesizing a Unicode keystroke (reliable for most native
/// text fields), then fall back to writing the clipboard and synthesizing ⌘V.
/// Requires Accessibility permission — `AXIsProcessTrusted()` gates the attempt so
/// the caller can guide the user to System Settings on first run.
@MainActor
final class CGEventTextInserter: TextInserter {
    private let log = Logger(subsystem: AppBrand.loggerSubsystem, category: "insert")

    /// The app that was frontmost when capture began. We restore its focus before
    /// posting keystrokes, since the review panel may have become key (spec §8/§13.6).
    private let targetProvider: @MainActor () -> NSRunningApplication?
    /// System-wide Secure Input lock. Used only to skip the keystroke-synthesis fallback:
    /// synthetic key events are silently swallowed under Secure Input, so there we defer to
    /// ⌘V / the clipboard fallback instead of typing into the void. Paste is NOT gated on this
    /// (openless gates the same way — secure-input check on the keystroke path only).
    private let isSecureInputActive: @MainActor () -> Bool

    init(
        targetProvider: @escaping @MainActor () -> NSRunningApplication? = { nil },
        isSecureInputActive: @escaping @MainActor () -> Bool = { IsSecureEventInputEnabled() }
    ) {
        self.targetProvider = targetProvider
        self.isSecureInputActive = isSecureInputActive
    }

    func insert(_ text: String) async throws {
        guard !text.isEmpty else { return }
        guard AccessibilityPermission.isTrusted else {
            throw InsertError.failed(AccessibilityPermission.guidance)
        }

        let target = targetProvider()
        // INSERT-TERMINAL-NEWLINE-006: a newline pasted into a shell executes a command.
        let safeText = ShellTargetSanitizer.sanitize(text, forTargetBundleID: target?.bundleIdentifier)
        guard !safeText.isEmpty else { return }

        // Re-assert the original target app's focus before posting. We do NOT gate on
        // `isActive`: a non-activating key panel can intercept keystrokes while the
        // target still reports active, so always re-activate to be safe (review #1 / §13.6).
        if let target {
            _ = target.activate()
            try? await Task.sleep(nanoseconds: 80_000_000)  // let focus settle
        }

        // Mechanism order (clipboard first; keystroke only when Secure Input is off — synthetic key
        // events are silently swallowed under Secure Input) is decided by InsertionStrategyResolver.
        for method in InsertionStrategyResolver.mechanismOrder(isSecureInputActive: isSecureInputActive()) {
            switch method {
            case .clipboard:
                if await pasteAndRestore(safeText) {
                    log.info("Inserted via clipboard paste (\(safeText.count, privacy: .public) chars)")
                    return
                }
            case .keystroke:
                if postUnicode(safeText) {
                    log.info("Inserted via CGEvent unicode fallback (\(safeText.count, privacy: .public) chars)")
                    return
                }
            }
        }

        throw InsertError.failed("既无法合成按键,也无法粘贴。已复制到剪贴板,请按 ⌘V。")
    }

    /// Posts the string as Unicode payloads on synthetic key events, chunked so each event
    /// stays under `CGEventKeyboardSetUnicodeString`'s ~20-UTF16-unit cap and never splits a
    /// grapheme cluster (INSERT-UNICODE-004). Posting the whole string in one event truncates
    /// long CJK/emoji on the HID layer.
    private func postUnicode(_ text: String) -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }
        source.userData = SyntheticEventTag.userData  // so our Fn tap ignores its own output
        for chunk in UnicodeKeystrokeChunker.chunks(text) {
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                return false
            }
            keyDown.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
            keyUp.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
        return true
    }

    private func pasteAndRestore(_ text: String) async -> Bool {
        let pasteboard = NSPasteboard.general
        let savedItems = cloneItems(pasteboard.pasteboardItems ?? [])
        pasteboard.clearContents()
        // CLIPBOARD-PRIVACY-002: mark our temporary paste payload transient + concealed so
        // clipboard-history managers (Maccy/Paste/…) and Universal Clipboard skip the dictated
        // text. ⌘V still reads `.string`; the markers only affect history capture.
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        pasteboard.writeObjects([item])

        let ourChangeCount = pasteboard.changeCount   // the write we just made
        let didPostPaste = postCommandV()
        try? await Task.sleep(nanoseconds: 280_000_000)
        // CLIPBOARD-CLOBBER-001: restore the user's clipboard only if nothing copied during
        // the paste window — a user copy made meanwhile must win (openless should_restore_clipboard).
        if pasteboard.changeCount == ourChangeCount {
            restore(items: savedItems, to: pasteboard)
        }
        return didPostPaste
    }

    private func cloneItems(_ items: [NSPasteboardItem]) -> [NSPasteboardItem] {
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

    private func restore(items: [NSPasteboardItem], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }

    /// Synthesizes ⌘V to paste whatever is on the clipboard.
    private func postCommandV() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }
        source.userData = SyntheticEventTag.userData  // so our Fn tap ignores its own output
        let vKeyCode: CGKeyCode = 9  // kVK_ANSI_V
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            return false
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}
