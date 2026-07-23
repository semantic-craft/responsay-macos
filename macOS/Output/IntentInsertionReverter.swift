import AppKit
import ApplicationServices
import OSLog
import ResponsayCore

/// 560 — executes an `IntentUndoPlan` against the focused field: delete the exact verified text, or
/// restore the selection it replaced. It only ever removes the verified text or writes back the
/// captured selection — it NEVER writes the raw transcript (that is the retired ↩原文 path).
///
/// It uses ONLY the precise, cursor-independent AX value write: read the field's value, replace the
/// LAST occurrence of the inserted text, write the whole value back. If the field doesn't allow an
/// AX value write (many web / Electron fields), it **refuses** (returns false) rather than fall back
/// to a caret-relative keystroke delete — the caret may have moved since the insert, and the undo
/// evidence proves the text is *present*, not *adjacent to the caret*. Refusing here is spec
/// decision #26 (证不了 → 拒绝自动改文档); a keystroke guess could corrupt the user's later edits.
/// Real-host behavior across native / web / Electron targets is HITL-verified in #568.
@MainActor
struct IntentInsertionReverter {
    private let targetProvider: @MainActor () -> NSRunningApplication?
    private let log = Logger(subsystem: AppBrand.loggerSubsystem, category: "intent-undo")

    init(targetProvider: @escaping @MainActor () -> NSRunningApplication?) {
        self.targetProvider = targetProvider
    }

    func execute(_ plan: IntentUndoPlan) async -> Bool {
        let old: String
        let new: String
        switch plan {
        case let .deleteInserted(text): old = text; new = ""
        case let .restoreSelection(replacing, with): old = replacing; new = with
        case .refuse: return false   // the VM decides refuse; never reached with a real plan
        }
        guard AccessibilityPermission.isTrusted, !old.isEmpty else {
            log.error("Intent undo skipped: accessibility not trusted or empty target")
            return false
        }
        if let target = targetProvider() {
            _ = target.activate()
            try? await Task.sleep(nanoseconds: 60_000_000)
        }
        let ok = replaceLastOccurrenceViaAX(old: old, new: new)
        log.info("Intent undo via AX value write \(ok ? "succeeded" : "refused (field not AX-settable)", privacy: .public)")
        return ok
    }

    /// Replace the LAST occurrence of `old` with `new` in the focused element's value. Cursor-
    /// independent (works even if the caret moved). Returns false — undo refused — when the value
    /// can't be read or isn't settable, so nothing in the document is guessed at.
    private func replaceLastOccurrenceViaAX(old: String, new: String) -> Bool {
        guard let element = focusedElement() else { return false }
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
              let current = valueRef as? String,
              let range = current.range(of: old, options: .backwards) else {
            return false
        }
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success,
              settable.boolValue else {
            return false
        }
        let newValue = current.replacingCharacters(in: range, with: new)
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
}
