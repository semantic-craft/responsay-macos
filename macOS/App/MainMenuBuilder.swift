import AppKit
import ResponsayCore

/// The AppKit main menu (#578). SwiftUI used to synthesize this; with the last scene gone the
/// app must provide it, or ⌘C/⌘V/⌘A stop working in every text field (Settings, main window,
/// correction panel). Standard-selector items only — first responder does the routing.
@MainActor
enum MainMenuBuilder {
    static func build() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 \(AppBrand.displayName)",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let settings = NSMenuItem(title: "设置…", action: #selector(AppMenuActions.openSettings), keyEquivalent: ",")
        settings.target = AppMenuActions.shared
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 \(AppBrand.displayName)",
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "隐藏其他",
                                         action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 \(AppBrand.displayName)",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu(appMenu, title: AppBrand.displayName))

        let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(submenu(edit, title: "编辑"))

        let window = NSMenu(title: "窗口")
        window.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        window.addItem(.separator())
        let cycle = NSMenuItem(
            title: "下一个窗口",
            action: #selector(AppMenuActions.cycleWindows(_:)),
            keyEquivalent: "`")
        cycle.keyEquivalentModifierMask = [.command]
        cycle.target = AppMenuActions.shared
        window.addItem(cycle)
        window.addItem(withTitle: "前置全部窗口",
                       action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        main.addItem(submenu(window, title: "窗口"))
        NSApp.windowsMenu = window

        return main
    }

    private static func submenu(_ menu: NSMenu, title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}

/// Menu target for app-owned actions (the responder chain has no object for these).
@MainActor
final class AppMenuActions: NSObject {
    static let shared = AppMenuActions()
    private let orderedWindows: () -> [NSWindow]
    private let keyWindow: () -> NSWindow?
    private let activateWindow: (NSWindow, Any?) -> Void

    init(
        orderedWindows: @escaping () -> [NSWindow] = { NSApp.orderedWindows },
        keyWindow: @escaping () -> NSWindow? = { NSApp.keyWindow },
        activateWindow: @escaping (NSWindow, Any?) -> Void = { window, sender in
            window.makeKeyAndOrderFront(sender)
        }
    ) {
        self.orderedWindows = orderedWindows
        self.keyWindow = keyWindow
        self.activateWindow = activateWindow
        super.init()
    }

    @objc func openSettings() { MacSettingsWindowController.shared.show() }

    /// The app builds its menu without a storyboard, so AppKit has no standard ⌘` item to route.
    /// Cycle only visible keyable document windows; non-activating capsule panels are excluded by
    /// `canBecomeKey`, while the floating Read Aloud reader remains a normal participant.
    @objc func cycleWindows(_ sender: Any?) {
        let candidates = orderedWindows().filter {
            $0.isVisible && !$0.isMiniaturized && $0.canBecomeKey
        }
        guard let next = Self.nextWindow(in: candidates, after: keyWindow()) else { return }
        activateWindow(next, sender)
    }

    static func nextWindow(in candidates: [NSWindow], after current: NSWindow?) -> NSWindow? {
        guard candidates.count > 1 else { return nil }
        let currentIndex = current.flatMap { current in
            candidates.firstIndex(where: { $0 === current })
        }
        let nextIndex = currentIndex.map { ($0 + 1) % candidates.count } ?? 0
        return candidates[nextIndex]
    }
}
