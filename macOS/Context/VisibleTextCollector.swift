import AppKit
import ApplicationServices
import ResponsayCore

/// 屏幕可见文字采集 — recursively walks the focused app's Accessibility tree and joins the visible
/// text, so the cloud LLM can read the screen the way Typeless does (报告 §8/§14). Bounded hard on
/// every axis (length / depth / node budget) so a deep web app can never stall a capture; on any
/// limit it returns the best-effort partial text instead of throwing.
///
/// Gated upstream twice: by `ScreenContextSettings` (the user toggle) and by the capture security
/// gate — secure password fields, sensitive apps, and sensitive URLs are already excluded before
/// this runs, so it never needs its own blacklist.
///
/// Assembly (smartJoin + head-truncation) lives in `ResponsayCore.VisibleTextComposer`;
/// this file only does the AX tree-order walk. Tree order ≈ document reading order and keeps
/// multi-column / grouped subtrees contiguous; the head carries the title/subject/entities the
/// LLM biasing needs most, so we keep the front and drop the tail (Typeless 同款).
///
/// Deliberately NOT `@MainActor`: the AX C API (`AXUIElementCopyAttributeValue` & friends,
/// `AXIsProcessTrusted`) is thread-safe, and the transient-terms harvest runs this walk from a
/// detached task — isolating to the MainActor would hop the whole walk (one AX IPC per node)
/// back onto the main thread and stall the UI on slow (Electron) hosts.
enum VisibleTextCollector {
    static let maxLength = 2000  // 采集 + 输出上限：一到预算就停遍历（砍头，少走 AX 节点）
    static let maxDepth = 30
    /// ponytail: a flat node budget is the cycle/runaway ceiling (AX trees can self-reference).
    /// If a real page ever needs deeper coverage, swap in a visited-CFHash set like
    /// `AccessibilityContextReader.findTextContextElement` uses.
    static let maxNodes = 1500

    /// nil when AX is untrusted or nothing readable was found; otherwise the visible text joined
    /// in tree order and head-truncated to `maxLength` by `VisibleTextComposer`.
    static func collect(from target: NSRunningApplication?) -> String? {
        let processIdentifier = (target ?? NSWorkspace.shared.frontmostApplication)?.processIdentifier
        return collect(processIdentifier: processIdentifier)
    }

    /// PID-bound variant for asynchronous capture work. The caller snapshots the frontmost app on
    /// the capture path before dispatching; a delayed AX walk therefore cannot drift into whichever
    /// app happens to become frontmost while the task is waiting to run.
    static func collect(processIdentifier: pid_t?) -> String? {
        guard AXIsProcessTrusted(), let processIdentifier else { return nil }
        let axApp = AXUIElementCreateApplication(processIdentifier)
        let root = focusedWindow(in: axApp) ?? axApp

        var fragments: [(text: String, isBody: Bool)] = []
        var length = 0
        var remainingNodes = maxNodes
        walk(root, depth: 0, fragments: &fragments, length: &length, remainingNodes: &remainingNodes)

        let composed = VisibleTextComposer.compose(fragments, maxLength: maxLength)
        return composed.isEmpty ? nil : composed
    }

    private static func walk(
        _ element: AXUIElement,
        depth: Int,
        fragments: inout [(text: String, isBody: Bool)],
        length: inout Int,
        remainingNodes: inout Int
    ) {
        guard depth <= maxDepth, length < maxLength, remainingNodes > 0 else { return }
        remainingNodes -= 1
        guard isVisible(element) else { return }

        switch stringAttr(element, kAXRoleAttribute) {
        case "AXStaticText", "AXTextField", "AXTextArea":
            append(stringAttr(element, kAXValueAttribute), isBody: true, &fragments, &length)
        case "AXButton", "AXLink", "AXCheckBox", "AXRadioButton", "AXMenuItem", "AXCell", "AXPopUpButton":
            append(stringAttr(element, kAXTitleAttribute), isBody: false, &fragments, &length)
        case "AXGroup", "AXScrollArea", "AXSplitGroup", "AXTabGroup", "AXOutline", "AXList",
             "AXTable", "AXWebArea", "AXToolbar", "AXRow", "AXColumn", "AXGenericElement", .none:
            break  // container: descend only, collect no text of its own
        default:
            let text = stringAttr(element, kAXValueAttribute)
                ?? stringAttr(element, kAXTitleAttribute)
                ?? stringAttr(element, kAXDescriptionAttribute)
            append(text, isBody: false, &fragments, &length)
        }

        for child in childArray(element) {
            guard length < maxLength, remainingNodes > 0 else { return }
            walk(child, depth: depth + 1, fragments: &fragments, length: &length, remainingNodes: &remainingNodes)
        }
    }

    private static func append(
        _ text: String?, isBody: Bool,
        _ fragments: inout [(text: String, isBody: Bool)], _ length: inout Int
    ) {
        guard let text, !text.isEmpty else { return }
        fragments.append((text, isBody))
        length += text.count
    }

    /// Body text runs join with a space; UI labels/buttons and body separate with a newline, so a
    /// page reads as prose with its chrome on its own lines (报告 §8.2 smartJoin).
    /// Thin forwarder — real implementation moved to `ResponsayCore.VisibleTextComposer.smartJoin`;
    /// kept here only for `Tests/ResponsayMacTests/ScreenContextTests.swift` compatibility.
    static func smartJoin(_ fragments: [(text: String, isBody: Bool)]) -> String {
        VisibleTextComposer.smartJoin(fragments)
    }

    // MARK: - AX helpers (self-contained)

    private static func isVisible(_ element: AXUIElement) -> Bool {
        if let hidden = boolAttr(element, kAXHiddenAttribute), hidden { return false }
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &raw) == .success,
              let value = raw, CFGetTypeID(value) == AXValueGetTypeID() else {
            return true  // no size info → optimistically keep
        }
        var size = CGSize.zero
        AXValueGetValue(value as! AXValue, .cgSize, &size)
        return size.width > 0 && size.height > 0
    }

    private static func focusedWindow(in app: AXUIElement) -> AXUIElement? {
        element(app, kAXFocusedWindowAttribute) ?? element(app, kAXMainWindowAttribute)
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success,
              let value = raw, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func childArray(_ element: AXUIElement) -> [AXUIElement] {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &raw) == .success
        else { return [] }
        return (raw as? [AXUIElement]) ?? []
    }

    private static func stringAttr(_ element: AXUIElement, _ attribute: String) -> String? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success else { return nil }
        return (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func boolAttr(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success else { return nil }
        return raw as? Bool
    }
}
