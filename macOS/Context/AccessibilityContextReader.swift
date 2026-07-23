import AppKit
import ApplicationServices
import OSLog
import ResponsayCore

@MainActor
final class AccessibilityContextReader {
    private let log = Logger(subsystem: AppBrand.loggerSubsystem, category: "context")

    /// Diagnostics from the most recent `readContext` (measurement only — not sent to the backend).
    private(set) var lastDiagnostics = ContextReadDiagnostics.empty

    func readContext(from target: NSRunningApplication?) -> ExpressionContext {
        let app = target ?? NSWorkspace.shared.frontmostApplication
        var context = ExpressionContext(
            appName: app?.localizedName,
            bundleIdentifier: app?.bundleIdentifier,
            hotwords: ContextHotwordSettings.biasingSets().weakPrompt)

        guard AccessibilityPermission.isTrusted, let app else {
            lastDiagnostics = .empty
            logContext(context, axTrusted: false)
            return context
        }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        let systemWide = AXUIElementCreateSystemWide()
        let focusedElement = elementAttribute(kAXFocusedUIElementAttribute, from: systemWide)
            ?? elementAttribute(kAXFocusedUIElementAttribute, from: axApp)
        let window = elementAttribute(kAXWindowAttribute, from: focusedElement)
            ?? focusedWindow(in: axApp)
        context.windowTitle = stringAttribute(kAXTitleAttribute, from: window)

        let textElement = textContextElement(preferred: focusedElement, window: window, app: axApp)
        if let textElement {
            applyTextContext(from: textElement, to: &context)
        }
        lastDiagnostics = diagnostics(textElement: textElement, focusedElement: focusedElement)

        logContext(context, axTrusted: true)
        return context
    }

    /// 434 — the focused field's full text + owning scene, for the auto-learn edit watcher.
    /// nil when AX is untrusted, no text element is found, or the value isn't a plain string
    /// (web/contenteditable fields without `kAXValue`). Capped so a giant document can't blow
    /// up the diff. Trimmed for snapshot stability (matches `stringAttribute`).
    func readFocusedFieldSnapshot(
        from target: NSRunningApplication? = nil
    ) -> (text: String, app: String, sceneID: String?, windowTitle: String?)? {
        guard AccessibilityPermission.isTrusted,
              let app = target ?? NSWorkspace.shared.frontmostApplication,
              let bundleId = app.bundleIdentifier else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        let systemWide = AXUIElementCreateSystemWide()
        let focusedElement = target == nil
            ? elementAttribute(kAXFocusedUIElementAttribute, from: systemWide)
                ?? elementAttribute(kAXFocusedUIElementAttribute, from: axApp)
            : elementAttribute(kAXFocusedUIElementAttribute, from: axApp)
                ?? elementAttribute(kAXFocusedUIElementAttribute, from: systemWide)
        let window = elementAttribute(kAXWindowAttribute, from: focusedElement) ?? focusedWindow(in: axApp)
        let windowTitle = stringAttribute(kAXTitleAttribute, from: window)
        let sceneToken = sceneToken(for: window) ?? windowTitle
        guard let textElement = textContextElement(preferred: focusedElement, window: window, app: axApp),
              let value = stringAttribute(kAXValueAttribute, from: textElement),
              !value.isEmpty else { return nil }
        let sceneID = sceneToken.map { "\(bundleId)::\($0)" }
        return (text: String(value.prefix(4000)), app: bundleId, sceneID: sceneID, windowTitle: windowTitle)
    }

    /// 560 — the insertion target's identity + selection, for the target-binding transaction. Binds
    /// to whoever is frontmost (ignoring our own non-activating panels) and reads THAT app's focused
    /// element directly — not the system-wide focus, which during review follows the panel's key
    /// field. `nil` when the only candidate is ourselves. Real-host behavior is HITL-verified (#568).
    func readInsertionTargetSnapshot(from fallbackTarget: NSRunningApplication? = nil) -> InsertionTargetSnapshot? {
        let front = NSWorkspace.shared.frontmostApplication
        let app = (front?.bundleIdentifier != nil && front?.bundleIdentifier != Bundle.main.bundleIdentifier)
            ? front : fallbackTarget
        guard let app, let bundleID = app.bundleIdentifier, bundleID != Bundle.main.bundleIdentifier else { return nil }
        guard AccessibilityPermission.isTrusted else {
            return InsertionTargetSnapshot(bundleID: bundleID, processID: app.processIdentifier, isEditable: false)
        }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        let focused = elementAttribute(kAXFocusedUIElementAttribute, from: axApp)
        let window = elementAttribute(kAXWindowAttribute, from: focused) ?? focusedWindow(in: axApp)
        let selectedText = stringAttribute(kAXSelectedTextAttribute, from: focused)
        return InsertionTargetSnapshot(
            bundleID: bundleID,
            processID: app.processIdentifier,
            windowTitle: stringAttribute(kAXTitleAttribute, from: window),
            isEditable: isTextInputElement(focused),
            selection: selectedText.map { SelectionEvidence(selectedText: $0) })
    }

    /// Editability of a specific element (shared shape with `isFocusedElementEditable`, but for an
    /// element we already resolved).
    private func isTextInputElement(_ element: AXUIElement?) -> Bool {
        guard let element else { return false }
        if isValueSettable(element) { return true }
        let role = stringAttribute(kAXRoleAttribute, from: element)
        return ["AXTextField", "AXTextArea", "AXComboBox", "AXSecureTextField"].contains(role ?? "")
    }

    /// Whether the target app's focused element accepts text input. 划词翻译 uses this to choose
    /// between **replacing** the selection in place (editable — Notes, input boxes) and showing the
    /// translation in a **preview card** (read-only — reading a PDF / web article / WeChat message,
    /// where there is nothing to overwrite). A keystroke replace always lands in the focused
    /// element, so the focused element's editability is the right signal for "can we replace".
    func isFocusedElementEditable(from target: NSRunningApplication? = nil) -> Bool {
        guard AccessibilityPermission.isTrusted,
              let app = target ?? NSWorkspace.shared.frontmostApplication else { return false }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        let systemWide = AXUIElementCreateSystemWide()
        let focused = target == nil
            ? elementAttribute(kAXFocusedUIElementAttribute, from: systemWide)
                ?? elementAttribute(kAXFocusedUIElementAttribute, from: axApp)
            : elementAttribute(kAXFocusedUIElementAttribute, from: axApp)
                ?? elementAttribute(kAXFocusedUIElementAttribute, from: systemWide)
        guard let focused else { return false }
        if isValueSettable(focused) { return true }
        let role = stringAttribute(kAXRoleAttribute, from: focused)
        return ["AXTextField", "AXTextArea", "AXComboBox", "AXSecureTextField"].contains(role ?? "")
    }

    /// AX reports `kAXValue` settable for editable text controls and not-settable for static /
    /// read-only text (a message bubble, a rendered PDF or web line).
    private func isValueSettable(_ element: AXUIElement) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success
            && settable.boolValue
    }

    private func diagnostics(textElement: AXUIElement?, focusedElement: AXUIElement?) -> ContextReadDiagnostics {
        let roleSource = textElement ?? focusedElement
        return ContextReadDiagnostics(
            role: roleSource.flatMap { stringAttribute(kAXRoleAttribute, from: $0) },
            hasTextElement: textElement != nil,
            markerCapable: respondsToMarkerRange(textElement) || respondsToMarkerRange(focusedElement))
    }

    /// Read-only probe: does the element expose `AXSelectedTextMarkerRange` (the web/contenteditable
    /// marker path the Round B reader will use)? Raw attribute key — not a public SDK symbol.
    private func respondsToMarkerRange(_ element: AXUIElement?) -> Bool {
        guard let element else { return false }
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &value) == .success
    }

    private func logContext(_ context: ExpressionContext, axTrusted: Bool) {
        log.info("Expression context captured; axTrusted \(axTrusted, privacy: .public); app \(String(describing: context.appName != nil), privacy: .public); windowTitle \(String(describing: context.windowTitle != nil), privacy: .public); selectedText \(String(describing: context.selectedText != nil), privacy: .public); beforeCursor \(String(describing: context.textBeforeCursor != nil), privacy: .public); afterCursor \(String(describing: context.textAfterCursor != nil), privacy: .public); hotwords \(context.hotwords.count, privacy: .public)")
    }

    private func focusedWindow(in app: AXUIElement) -> AXUIElement? {
        elementAttribute(kAXFocusedWindowAttribute, from: app)
            ?? elementAttribute(kAXMainWindowAttribute, from: app)
    }

    private func elementAttribute(_ attribute: String, from element: AXUIElement?) -> AXUIElement? {
        guard let element else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let axElement = value as! AXUIElement? else {
            return nil
        }
        return axElement
    }

    private func elementArrayAttribute(_ attribute: String, from element: AXUIElement?) -> [AXUIElement] {
        guard let element else { return [] }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return []
        }
        if let elements = value as? [AXUIElement] {
            return elements
        }
        if let element = value as! AXUIElement? {
            return [element]
        }
        return []
    }

    private func stringAttribute(_ attribute: String, from element: AXUIElement?) -> String? {
        guard let element else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func urlAttribute(_ attribute: String, from element: AXUIElement?) -> URL? {
        guard let element else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? URL
    }

    private func sceneToken(for window: AXUIElement?) -> String? {
        stringAttribute("AXIdentifier", from: window)
            ?? urlAttribute("AXDocument", from: window)?.absoluteString
            ?? stringAttribute("AXDocument", from: window)
    }

    private func applyTextContext(from element: AXUIElement, to context: inout ExpressionContext) {
        let text = stringAttribute(kAXValueAttribute, from: element)
        let range = selectedRange(in: element)
        let selectedText = stringAttribute(kAXSelectedTextAttribute, from: element)
            ?? selectedSubstring(in: text, range: range)
            ?? stringForRange(range, in: element)
        let aroundCursor = textAroundCursor(in: text, range: range, element: element)

        context.selectedText = selectedText
        context.textBeforeCursor = aroundCursor.before
        context.textAfterCursor = aroundCursor.after
    }

    private func textContextElement(
        preferred: AXUIElement?,
        window: AXUIElement?,
        app: AXUIElement
    ) -> AXUIElement? {
        if hasTextContext(preferred) {
            return preferred
        }

        let roots = [window, focusedWindow(in: app), preferred, Optional(app)].compactMap(\.self)
        var visited = Set<CFHashCode>()
        var remainingNodes = 220

        for root in roots {
            if let match = findTextContextElement(in: root, depth: 0, visited: &visited, remainingNodes: &remainingNodes) {
                return match
            }
        }
        return nil
    }

    private func findTextContextElement(
        in element: AXUIElement,
        depth: Int,
        visited: inout Set<CFHashCode>,
        remainingNodes: inout Int
    ) -> AXUIElement? {
        guard depth <= 8, remainingNodes > 0 else { return nil }
        remainingNodes -= 1

        let identity = CFHash(element)
        guard visited.insert(identity).inserted else { return nil }
        if hasTextContext(element) {
            return element
        }

        for attribute in [kAXVisibleChildrenAttribute, kAXChildrenAttribute, kAXSelectedChildrenAttribute] {
            for child in elementArrayAttribute(attribute, from: element) {
                if let match = findTextContextElement(in: child, depth: depth + 1, visited: &visited, remainingNodes: &remainingNodes) {
                    return match
                }
            }
        }
        return nil
    }

    private func hasTextContext(_ element: AXUIElement?) -> Bool {
        guard let element else { return false }
        if stringAttribute(kAXSelectedTextAttribute, from: element) != nil {
            return true
        }

        guard let range = selectedRange(in: element) else {
            return false
        }
        if stringAttribute(kAXValueAttribute, from: element) != nil {
            return true
        }
        if range.length > 0, stringForRange(range, in: element) != nil {
            return true
        }
        let probeRange = CFRange(location: max(0, range.location - 1), length: range.location > 0 ? 1 : 0)
        return stringForRange(probeRange, in: element) != nil
    }

    private func selectedRange(in element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let axValue = value as! AXValue? else {
            return nil
        }

        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range), range.location >= 0 else {
            return nil
        }
        return range
    }

    private func selectedSubstring(in text: String?, range: CFRange?) -> String? {
        guard let text, let range, range.length > 0 else { return nil }
        let nsText = text as NSString
        guard range.location <= nsText.length,
              range.location + range.length <= nsText.length else {
            return nil
        }
        return nsText.substring(with: NSRange(location: range.location, length: range.length))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stringForRange(_ range: CFRange?, in element: AXUIElement?) -> String? {
        guard let element, var range, range.location >= 0, range.length >= 0 else { return nil }
        guard let axRange = AXValueCreate(.cfRange, &range) else { return nil }

        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            axRange,
            &value
        ) == .success else {
            return nil
        }
        return (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func textAroundCursor(in text: String?, range: CFRange?, element: AXUIElement?) -> (before: String?, after: String?) {
        guard let range else { return (nil, nil) }
        guard let text else {
            let cursorStart = max(0, range.location)
            let cursorEnd = max(cursorStart, range.location + max(range.length, 0))
            let beforeRange = CFRange(location: max(0, cursorStart - 700), length: min(700, cursorStart))
            let before = stringForRange(beforeRange, in: element)
            let after = stringForRange(CFRange(location: cursorEnd, length: 700), in: element)
            return (before, after)
        }

        let nsText = text as NSString
        let cursorStart = max(0, min(range.location, nsText.length))
        let cursorEnd = max(cursorStart, min(range.location + max(range.length, 0), nsText.length))

        let beforeStart = max(0, cursorStart - 700)
        let before = nsText
            .substring(with: NSRange(location: beforeStart, length: cursorStart - beforeStart))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let afterLength = min(700, nsText.length - cursorEnd)
        let after = nsText
            .substring(with: NSRange(location: cursorEnd, length: afterLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (before.isEmpty ? nil : before, after.isEmpty ? nil : after)
    }
}
