import AppKit
import ApplicationServices
import OSLog
import ResponsayCore

/// Revert AI (P0b): swaps the just-inserted AI text in the focused field back to the raw transcript.
///
/// Strategy, in order:
/// 1. **AX value write** — read the focused element's `kAXValueAttribute`, replace the LAST occurrence
///    of the inserted `polished` text with `raw`, and write the whole value back. Precise and
///    cursor-independent (works even if the caret moved), when the field allows AX writes.
/// 2. **Keystroke fallback** — when AX value isn't settable (some web/Electron fields): select the
///    just-inserted text with Shift+←×N and let the inserter overwrite the selection with `raw`.
///    Assumes the caret is still right after the insertion (true within the short revert window).
///
/// After a successful replace it re-baselines the auto-learn watcher (`onReverted`) so the
/// polished→raw change is NOT mistaken for a user correction.
@MainActor
struct InsertionReverter {
    private let targetProvider: @MainActor () -> NSRunningApplication?
    private let rawInserter: any TextInserter
    private let onReverted: @MainActor () -> Void
    private let log = Logger(subsystem: AppBrand.loggerSubsystem, category: "revert")

    init(
        targetProvider: @escaping @MainActor () -> NSRunningApplication?,
        rawInserter: any TextInserter,
        onReverted: @escaping @MainActor () -> Void
    ) {
        self.targetProvider = targetProvider
        self.rawInserter = rawInserter
        self.onReverted = onReverted
    }

    func revert(_ revertable: RevertableInsertion) async -> Bool {
        guard AccessibilityPermission.isTrusted else {
            log.error("Revert skipped: accessibility not trusted")
            return false
        }
        // Re-assert the target's focus (the capsule chip is a non-activating panel, but be safe).
        if let target = targetProvider() {
            _ = target.activate()
            try? await Task.sleep(nanoseconds: 60_000_000)
        }

        if revertViaAXValue(revertable) {
            log.info("Reverted via AX value write")
            onReverted()
            return true
        }

        let ok = await revertViaKeystroke(revertable)
        log.info("Revert keystroke fallback \(ok ? "succeeded" : "failed", privacy: .public)")
        if ok { onReverted() }
        return ok
    }

    // MARK: - AX value write (precise)

    private func revertViaAXValue(_ revertable: RevertableInsertion) -> Bool {
        guard let element = focusedElement() else { return false }
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
              let current = valueRef as? String,
              // Replace the LAST occurrence — that's the text we just inserted.
              let range = current.range(of: revertable.polished, options: .backwards) else {
            return false
        }
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success,
              settable.boolValue else {
            return false
        }
        let newValue = current.replacingCharacters(in: range, with: revertable.raw)
        return AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, newValue as CFString) == .success
    }

    private func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused, CFGetTypeID(element) == AXUIElementGetTypeID() else {
            return nil
        }
        return (element as! AXUIElement)
    }

    // MARK: - Keystroke fallback (select inserted text, overwrite with raw)

    private func revertViaKeystroke(_ revertable: RevertableInsertion) async -> Bool {
        // One Shift+← per grapheme selects back over the just-inserted text (caret assumed at its end).
        let count = revertable.polished.count
        guard count > 0, count <= 4000, selectBackward(count) else { return false }
        try? await Task.sleep(nanoseconds: 40_000_000)
        do {
            try await rawInserter.insert(revertable.raw)   // paste overwrites the selection
            return true
        } catch {
            log.error("Revert keystroke insert failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func selectBackward(_ count: Int) -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }
        let leftArrow: CGKeyCode = 123
        for _ in 0..<count {
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: leftArrow, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: leftArrow, keyDown: false) else {
                return false
            }
            down.flags = .maskShift
            up.flags = .maskShift
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
        return true
    }
}
