import AppKit
import ApplicationServices
import Carbon
import OSLog
import ResponsayCore

@MainActor
final class CaptureGateContextReader {
    private let log = Logger(subsystem: AppBrand.loggerSubsystem, category: "context")

    func readCaptureContext(from target: NSRunningApplication?) -> CaptureContext {
        let app = target ?? NSWorkspace.shared.frontmostApplication
        // System-wide Secure Input lock (a focused password field, or any app holding it) is a
        // role-independent privacy signal — it stays true even when AX can't read the field, so it
        // closes the unknown-/inaccessible-focus hole the AX role check alone leaves open
        // (SECURE-DETECT-001 / INSERT-AX-UNKNOWN-010). openless probes the same.
        let secureInput = IsSecureEventInputEnabled()
        guard AccessibilityPermission.isTrusted, let app else {
            return CaptureContext(bundleID: app?.bundleIdentifier, isSecureTextField: secureInput)
        }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        let systemWide = AXUIElementCreateSystemWide()
        let focusedElement = elementAttribute(kAXFocusedUIElementAttribute, from: systemWide)
            ?? elementAttribute(kAXFocusedUIElementAttribute, from: axApp)
        let window = elementAttribute(kAXWindowAttribute, from: focusedElement)
            ?? focusedWindow(in: axApp)
        let secure = secureInput || isSecureTextField(focusedElement: focusedElement)
        let url = browserURL(bundleID: app.bundleIdentifier, focusedElement: focusedElement, window: window, app: axApp)

        log.info("Capture gate context captured; bundle \(app.bundleIdentifier ?? "unknown", privacy: .public); secureField \(secure, privacy: .public); browserURL \(String(describing: url != nil), privacy: .public)")
        return CaptureContext(bundleID: app.bundleIdentifier, isSecureTextField: secure, url: url)
    }

    /// Whether the target app's focused element can receive inserted text. Drives the copy-pill
    /// fallback: `false` → there is no editable target, so a dictation result is offered as a 📋
    /// (`.copied`) instead of being ⌘V-pasted into nothing. Conservative — returns `true` (allow the
    /// normal insert) whenever AX is untrusted or the element is editable by any signal; returns
    /// `false` only when confidently non-editable (an AX-exposing app with no focused element, or a
    /// focused element that exposes no settable text). A false negative just shows a harmless copy
    /// pill; a false positive would lose the text, so the unknown cases favor inserting.
    func hasEditableFocus(in target: NSRunningApplication?) -> Bool {
        let app = target ?? NSWorkspace.shared.frontmostApplication
        guard AccessibilityPermission.isTrusted, let app else { return true }

        // Apps whose AX editability signal is unreliable (WeChat 4.x is AX-opaque; Codex desktop maps
        // its editor non-standardly) but where the user dictates into an input box — trust the app
        // over the AX probe and insert, rather than fire a wrong copy pill. Mirrors Typeless's app
        // allow-list; see `ForceInsertApps` for the trade-off.
        if ForceInsertApps.contains(app.bundleIdentifier) { return true }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        let systemWide = AXUIElementCreateSystemWide()
        let focused = elementAttribute(kAXFocusedUIElementAttribute, from: systemWide)
            ?? elementAttribute(kAXFocusedUIElementAttribute, from: axApp)

        // URL allow-list: browser web editors (Google Docs / Tencent Docs / Figma) whose AX often
        // can't be read as editable — mirror Typeless's url_blacklist/url_whitelist. `browserURL`
        // returns nil for non-browsers, so this falls straight through elsewhere.
        let window = elementAttribute(kAXWindowAttribute, from: focused) ?? focusedWindow(in: axApp)
        if let url = browserURL(bundleID: app.bundleIdentifier, focusedElement: focused, window: window, app: axApp),
           ForceInsertURLs.matches(url) {
            return true
        }

        guard let focused else {
            // "Nothing focused" is only meaningful when the app exposes its UI to accessibility at
            // all. AX-opaque apps (WeChat 4.x: Qt content tree unexposed, focus reads kAXErrorNoValue
            // even with the cursor blinking in the chat input box) look identical to the desktop
            // here — but they are *unknown*, not non-editable, and unknown must insert
            // (WECHAT-AX-OPAQUE-001; a wrong pill here fired on every WeChat dictation).
            return windowExposesOnlyChrome(in: axApp)
        }

        // Settable kAXValue is the strongest editable signal for native fields.
        if isAttributeSettable(kAXValueAttribute, of: focused) { return true }
        // Web contenteditable / rich editors expose a settable selection range rather than kAXValue.
        if isAttributeSettable(kAXSelectedTextRangeAttribute, of: focused) { return true }
        // Known editable roles cover fields that don't advertise settable attributes cleanly.
        if let role = stringAttribute(kAXRoleAttribute, from: focused),
           ["AXTextField", "AXTextArea", "AXMultiLineTextField", "AXMultiLineTextArea",
            "AXComboBox", "AXSearchField"].contains(role) {
            return true
        }
        return false
    }

    /// Whether the app's focused window exposes nothing beyond the free window-chrome buttons
    /// (close/minimize/zoom) — i.e. its real content tree is invisible to accessibility, so a
    /// "no focused element" answer carries no information. WeChat 4.x is the canonical case: its
    /// window's only AX children are the three traffic-light AXButtons.
    /// ponytail: chrome-only heuristic; if another opaque app slips through, the upgrade path is
    /// setting "AXManualAccessibility" on the app element to force Qt/Chromium to build the tree.
    private func windowExposesOnlyChrome(in axApp: AXUIElement) -> Bool {
        guard let window = focusedWindow(in: axApp) else { return false }
        let children = elementArrayAttribute(kAXChildrenAttribute, from: window)
        return children.allSatisfy { stringAttribute(kAXRoleAttribute, from: $0) == "AXButton" }
    }

    private func isAttributeSettable(_ attribute: String, of element: AXUIElement) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success
            && settable.boolValue
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

    private func urlAttribute(_ attribute: String, from element: AXUIElement?) -> String? {
        guard let element else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        if let url = value as? URL {
            return url.absoluteString
        }
        return (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isSecureTextField(focusedElement: AXUIElement?) -> Bool {
        guard let focusedElement else { return false }
        var current: AXUIElement? = focusedElement
        var remainingHops = 5
        while let element = current, remainingHops >= 0 {
            if isSecureElement(element) {
                return true
            }
            current = elementAttribute(kAXParentAttribute, from: element)
            remainingHops -= 1
        }
        return false
    }

    private func isSecureElement(_ element: AXUIElement) -> Bool {
        [
            kAXRoleAttribute,
            kAXSubroleAttribute,
            "AXRoleDescription",
            kAXDescriptionAttribute,
            kAXTitleAttribute,
            "AXPlaceholderValue"
        ]
        .compactMap { stringAttribute($0, from: element)?.lowercased() }
        .contains { value in
            value.contains("secure") || value.contains("password") || value.contains("密码")
        }
    }

    private func browserURL(
        bundleID: String?,
        focusedElement: AXUIElement?,
        window: AXUIElement?,
        app: AXUIElement
    ) -> String? {
        guard isBrowser(bundleID: bundleID) else { return nil }
        if let url = addressBarURL(in: window) {
            return url
        }
        var visited = Set<CFHashCode>()
        var remainingNodes = 160
        for root in [focusedElement, window, Optional(app)].compactMap(\.self) {
            if let url = firstURL(in: root, depth: 0, visited: &visited, remainingNodes: &remainingNodes) {
                return url
            }
        }
        return nil
    }

    private func isBrowser(bundleID: String?) -> Bool {
        switch bundleID {
        case "com.google.Chrome", "com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.microsoft.edgemac":
            return true
        default:
            return false
        }
    }

    private func addressBarURL(in window: AXUIElement?) -> String? {
        guard let window else { return nil }
        var visited = Set<CFHashCode>()
        var remainingNodes = 220
        return firstAddressBarURL(in: window, depth: 0, visited: &visited, remainingNodes: &remainingNodes)
    }

    private func firstAddressBarURL(
        in element: AXUIElement,
        depth: Int,
        visited: inout Set<CFHashCode>,
        remainingNodes: inout Int
    ) -> String? {
        guard depth <= 7, remainingNodes > 0 else { return nil }
        remainingNodes -= 1

        let identity = CFHash(element)
        guard visited.insert(identity).inserted else { return nil }
        if isBrowserAddressElement(element),
           let value = stringAttribute(kAXValueAttribute, from: element),
           let url = normalizedURLString(value) {
            return url
        }

        for attribute in [kAXVisibleChildrenAttribute, kAXChildrenAttribute, kAXSelectedChildrenAttribute] {
            for child in elementArrayAttribute(attribute, from: element) {
                if let url = firstAddressBarURL(in: child, depth: depth + 1, visited: &visited, remainingNodes: &remainingNodes) {
                    return url
                }
            }
        }
        return nil
    }

    private func isBrowserAddressElement(_ element: AXUIElement) -> Bool {
        [
            "AXIdentifier",
            "AXRoleDescription",
            kAXDescriptionAttribute,
            kAXTitleAttribute,
            "AXPlaceholderValue",
            "AXHelp"
        ]
        .compactMap { stringAttribute($0, from: element)?.lowercased() }
        .contains { value in
            value.contains("address") || value.contains("url") || value.contains("smart search")
        }
    }

    private func normalizedURLString(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if value.hasPrefix("http://") || value.hasPrefix("https://") ||
            value.hasPrefix("chrome://") || value.hasPrefix("about:") {
            return value
        }
        if value.contains(".") && !value.contains(" ") {
            return "https://\(value)"
        }
        return nil
    }

    private func firstURL(
        in element: AXUIElement,
        depth: Int,
        visited: inout Set<CFHashCode>,
        remainingNodes: inout Int
    ) -> String? {
        guard depth <= 7, remainingNodes > 0 else { return nil }
        remainingNodes -= 1

        let identity = CFHash(element)
        guard visited.insert(identity).inserted else { return nil }
        if let url = urlAttribute("AXURL", from: element) ?? urlAttribute("AXDocument", from: element) {
            return url
        }

        for attribute in [kAXVisibleChildrenAttribute, kAXChildrenAttribute, kAXSelectedChildrenAttribute] {
            for child in elementArrayAttribute(attribute, from: element) {
                if let url = firstURL(in: child, depth: depth + 1, visited: &visited, remainingNodes: &remainingNodes) {
                    return url
                }
            }
        }
        return nil
    }
}
