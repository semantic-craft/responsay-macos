import AppKit
import ApplicationServices
import OSLog
import ResponsayCore

/// Copy the current selection by **triggering the app's own "Copy" menu item via Accessibility**
/// (not a synthetic ⌘C keystroke), then reading the pasteboard. More reliable than keystroke
/// simulation in apps like WeChat (微信) where AX selected-text is unavailable AND synthetic ⌘C is
/// flaky — pressing the menu item directly invokes the app's copy command. Reuses
/// `ClipboardCopier`'s sentinel + backup/restore machinery; only the *trigger* differs.
///
/// Technique (same as Copi / openai-translator): scan the menu bar for the item whose Cmd-key
/// equivalent is "c" with no extra modifiers (= Copy, localization-independent), and AXPress it.
@MainActor
enum MenuActionCopier {
    private static let log = Logger(subsystem: AppBrand.loggerSubsystem, category: "menu-action-copier")

    static func copy(from target: NSRunningApplication?) async -> String? {
        guard let app = target ?? NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let copyItem = findCopyMenuItem(in: axApp) else {
            log.info("No Copy menu item found; skipping menu-action path")
            return nil
        }
        // Reuse ClipboardCopier's pasteboard backup/sentinel/restore; swap the trigger from a
        // synthetic ⌘C to pressing the located Copy menu item.
        return await ClipboardCopier.copy(from: target) {
            AXUIElementPerformAction(copyItem, kAXPressAction as CFString) == .success
        }
    }

    // MARK: - Locating the Copy menu item

    private static func findCopyMenuItem(in axApp: AXUIElement) -> AXUIElement? {
        guard let menuBar = element(axApp, kAXMenuBarAttribute) else { return nil }
        return searchCopyItem(in: menuBar, depth: 0)
    }

    /// Depth-first search for a menu item bound to ⌘C (cmd char "c", no extra modifiers).
    /// `kAXMenuItemCmdModifiersAttribute == 0` means Command only (no ⇧/⌥/⌃), so this matches
    /// "Copy" and not "Copy as…/⌘⇧C" etc. Bounded depth keeps the AX walk cheap.
    private static func searchCopyItem(in element: AXUIElement, depth: Int) -> AXUIElement? {
        guard depth <= 5 else { return nil }
        if let ch = string(element, kAXMenuItemCmdCharAttribute)?.lowercased(), ch == "c",
           int(element, kAXMenuItemCmdModifiersAttribute) == 0 {
            return element
        }
        for child in children(element) {
            if let found = searchCopyItem(in: child, depth: depth + 1) { return found }
        }
        return nil
    }

    // MARK: - AX helpers

    private static func element(_ el: AXUIElement, _ attr: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success,
              let child = value as! AXUIElement? else { return nil }
        return child
    }

    private static func children(_ el: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &value) == .success,
              let kids = value as? [AXUIElement] else { return [] }
        return kids
    }

    private static func string(_ el: AXUIElement, _ attr: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func int(_ el: AXUIElement, _ attr: String) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success,
              let number = value as? NSNumber else { return nil }
        return number.intValue
    }
}
